import { connection, mdns } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { Prefix, hostAllowed, scanHosts, normalizeOrigin, originHost, validMarker, legacyPage, ServiceMarker } from '../model/Protocol';
import { Transport } from './Transport';

export interface LocalNetwork { key: string; prefixes: Prefix[]; gateways: string[]; }
export interface FoundService { origin: string; name: string; legacy: boolean; }

export async function localNetwork(): Promise<LocalNetwork> {
  const handle = await connection.getDefaultNet();
  const caps = await connection.getNetCapabilities(handle);
  const bearers = caps.bearerTypes;
  if (bearers.includes(connection.NetBearType.BEARER_VPN) || bearers.includes(connection.NetBearType.BEARER_CELLULAR) ||
    !bearers.some((type: number) => type === connection.NetBearType.BEARER_WIFI || type === connection.NetBearType.BEARER_ETHERNET)) {
    throw new Error('请连接 Wi-Fi 或以太网；蜂窝网络及 VPN 不执行局域网连接');
  }
  const props = await connection.getConnectionProperties(handle);
  const prefixes: Prefix[] = props.linkAddresses.map((link: connection.LinkAddress): Prefix =>
    ({ address: link.address.address, length: link.prefixLength }));
  return { key: `${handle.netId}:${JSON.stringify(prefixes)}`, prefixes: prefixes,
    gateways: props.routes.filter((route: connection.RouteInfo) => route.hasGateway).map((route: connection.RouteInfo) => route.gateway.address) };
}

export class Discovery {
  private generation: number = 0;
  private transport: Transport = new Transport();
  private browser?: mdns.DiscoveryService;
  private deadlineTimer: number = -1;
  private networkTimer: number = -1;

  stop(): void {
    this.generation++;
    this.transport.cancel();
    clearTimeout(this.deadlineTimer);
    clearInterval(this.networkTimer);
    if (this.browser) {
      try { this.browser.stopSearchingMDNS(); this.browser.off('serviceFound'); this.browser.off('serviceLost'); } catch (_) {}
      this.browser = undefined;
    }
  }

  async verify(input: string, network: LocalNetwork, name: string = 'LanClip'): Promise<FoundService> {
    const origin = normalizeOrigin(input);
    if (!hostAllowed(originHost(origin), network.prefixes)) { throw new Error('地址不在当前网络实际前缀中'); }
    const response = await this.transport.request(`${origin}/.well-known/lanclip`, '', 'GET', undefined, 1800, 65536);
    if ((await localNetwork()).key !== network.key) { throw new Error('网络已切换，请重试'); }
    if (response.statusCode === 200) {
      if (!(response.headers['content-type'] || '').toString().toLowerCase().includes('application/json')) { throw new Error('服务标识不是 JSON'); }
      const marker = response.toJSON() as ServiceMarker;
      if (!validMarker(marker)) { throw new Error('服务标识不符合 LanClip 协议'); }
      return { origin: origin, name: name, legacy: false };
    }
    if (response.statusCode === 404 || response.statusCode === 405) {
      const page = await this.transport.request(`${origin}/`, '', 'GET', undefined, 1800, 512 * 1024);
      if (page.statusCode === 200 && legacyPage(page.toString())) { return { origin: origin, name: name, legacy: true }; }
    }
    throw new Error('该地址未通过 LanClip 身份验证');
  }

  async scan(context: common.UIAbilityContext, ports: number[], history: string[],
    onFound: (service: FoundService) => void, onProgress: (message: string) => void): Promise<void> {
    this.stop();
    const generation = this.generation;
    const network = await localNetwork();
    const seen: Set<string> = new Set();
    const revisions: Map<string, number> = new Map();
    let revision = 0;
    let changed = false;
    const emit = (service: FoundService): void => {
      if (generation !== this.generation || seen.has(service.origin)) { return; }
      seen.add(service.origin); onFound(service);
    };
    this.networkTimer = setInterval(() => {
      localNetwork().then((current: LocalNetwork) => {
        if (generation !== this.generation) { return; }
        if (current.key !== network.key) { changed = true; this.stop(); onProgress('网络已切换，请重新扫描'); }
      }).catch(() => { if (generation !== this.generation) { return; } changed = true; this.stop(); onProgress('网络不可用，扫描已取消'); });
    }, 1000);
    const started = Date.now();
    this.deadlineTimer = setTimeout(() => { if (generation !== this.generation) { return; } this.stop(); onProgress(`扫描时间已到 · 发现 ${seen.size} 个服务；未发现的可手动输入地址`); }, 20000);
    try {
      this.browser = mdns.createDiscoveryService(context, '_lanclip._tcp');
      this.browser.on('serviceFound', (info: mdns.LocalServiceInfo) => {
        const currentRevision = ++revision;
        revisions.set(info.serviceName, currentRevision);
        mdns.resolveLocalService(context, info).then(async (resolved: mdns.LocalServiceInfo) => {
          const attrs: Map<string, string> = new Map();
          resolved.serviceAttribute?.forEach((attribute: mdns.ServiceAttribute) => {
            attrs.set(attribute.key, String.fromCharCode(...attribute.value));
          });
          if (!/^\.?_lanclip\._tcp\.?$/i.test(resolved.serviceType) || attrs.get('service') !== 'lanclip' ||
            attrs.get('protocolVersion') !== '1' || attrs.get('scheme') !== 'http' || !resolved.host || !resolved.port) { return; }
          if (generation !== this.generation || revisions.get(info.serviceName) !== currentRevision) { return; }
          const service = await this.verify(`http://${resolved.host.address}:${resolved.port}`, network, resolved.serviceName);
          // Broadcasts always require the new HTTP marker, never legacy HTML.
          if (!service.legacy && revisions.get(info.serviceName) === currentRevision) { emit(service); }
        }).catch(() => {});
      });
      this.browser.on('serviceLost', (info: mdns.LocalServiceInfo) => { revisions.delete(info.serviceName); });
      this.browser.startSearchingMDNS();
    } catch (_) { onProgress('mDNS 暂不可用，继续有限端口探测'); }
    const candidates: string[] = [];
    history.forEach((value: string) => {
      try { const origin = normalizeOrigin(value); if (hostAllowed(originHost(origin), network.prefixes)) { candidates.push(origin); } } catch (_) {}
    });
    const hosts = Array.from(new Set(network.gateways.filter((host: string) => hostAllowed(host, network.prefixes)).concat(scanHosts(network.prefixes))));
    hosts.forEach((host: string) => ports.forEach((port: number) => candidates.push(`http://${host}:${port}`)));
    const unique = Array.from(new Set(candidates)).slice(0, 2048);
    let cursor = 0;
    let completed = 0;
    const worker = async (): Promise<void> => {
      while (cursor < unique.length && generation === this.generation && Date.now() - started < 19000) {
        const candidate = unique[cursor++];
        try { emit(await this.verify(candidate, network)); } catch (_) {}
        completed++;
        if (generation === this.generation) { onProgress(`已探测 ${completed}/${unique.length} · 发现 ${seen.size} 个服务`); }
      }
    };
    try {
      const workers: Promise<void>[] = [];
      for (let index = 0; index < 8; index++) { workers.push(worker()); }
      await Promise.all(workers);
      // Give mDNS a bounded discovery window even when the subnet cannot be traversed.
      while (generation === this.generation && Date.now() - started < 10000) { await new Promise<void>((resolve) => setTimeout(resolve, 200)); }
      if (!changed && generation === this.generation) {
        onProgress(`扫描结束 · 发现 ${seen.size} 个服务${network.prefixes.some((p: Prefix) => p.length < 24) ? '；大子网仅使用 mDNS/最近地址，请手动输入遗漏服务' : '；未扫描到可手动输入地址'}`);
      }
    } finally { if (generation === this.generation) { this.stop(); } }
  }
}
