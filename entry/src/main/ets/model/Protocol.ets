// Pure policy: deliberately accepts numeric RFC1918 IPv4 origins only.
export interface Prefix { address: string; length: number; }
export interface ServiceMarker {
  service: string;
  protocolVersion: number;
  webPath: string;
  apiPath: string;
  webSocketPath: string;
  authRequired: boolean;
  capabilities: string[];
}
export function ipv4(value: string): number {
  if (!/^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$/.test(value)) { return -1; }
  const parts = value.split('.').map((part: string) => Number(part));
  if (parts.some((part: number) => part > 255)) { return -1; }
  return parts.reduce((sum: number, part: number) => sum * 256 + part, 0);
}
export function privateIPv4(value: string): boolean {
  const n = ipv4(value);
  return n >= 167772160 && n <= 184549375 || n >= 2886729728 && n <= 2887778303 ||
    n >= 3232235520 && n <= 3232301055;
}
export function inPrefix(host: string, prefix: Prefix): boolean {
  const a = ipv4(host);
  const b = ipv4(prefix.address);
  const size = Math.pow(2, 32 - prefix.length);
  return a >= 0 && b >= 0 && prefix.length >= 1 && prefix.length <= 32 &&
    Math.floor(a / size) === Math.floor(b / size);
}
export function hostAllowed(host: string, prefixes: Prefix[]): boolean {
  return privateIPv4(host) && prefixes.some((prefix: Prefix) => inPrefix(host, prefix));
}
export function normalizeOrigin(input: string): string {
  const value = input.trim();
  const match = /^(https?):\/\/((?:\d{1,3}\.){3}\d{1,3})(?::(\d{1,5}))?\/?$/.exec(
    value.includes('://') ? value : `http://${value}`);
  if (!match || !privateIPv4(match[2])) { throw new Error('请输入当前局域网的私有 IPv4 地址，例如 http://192.168.1.2:9000'); }
  const port = match[3] ? Number(match[3]) : match[1] === 'https' ? 443 : 80;
  if (port < 1 || port > 65535) { throw new Error('端口应为 1–65535'); }
  return `${match[1]}://${match[2]}:${port}`;
}
export function originHost(origin: string): string { return origin.split('/')[2].split(':')[0]; }
export function parsePorts(input: string): number[] {
  const parts = input.split(/[,，\s]+/).filter((part: string) => part.length > 0);
  if (parts.length === 0 || parts.length > 8 || parts.some((part: string) => !/^\d{1,5}$/.test(part) || Number(part) < 1 || Number(part) > 65535)) {
    throw new Error('请填写 1–8 个有效端口，用逗号分隔');
  }
  return Array.from(new Set(parts.map((part: string) => Number(part))));
}
export function numberToIPv4(n: number): string {
  return [Math.floor(n / 16777216), Math.floor(n / 65536) % 256, Math.floor(n / 256) % 256, n % 256].join('.');
}
// A large subnet is never silently treated as /24 or exhaustively traversed.
export function scanHosts(prefixes: Prefix[], maximum: number = 256): string[] {
  const hosts: string[] = [];
  for (const prefix of prefixes) {
    const n = ipv4(prefix.address);
    if (!privateIPv4(prefix.address) || prefix.length < 24 || prefix.length > 30) { continue; }
    const size = Math.pow(2, 32 - prefix.length);
    const base = Math.floor(n / size) * size;
    for (let offset = 1; offset < size - 1 && hosts.length < maximum; offset++) {
      const host = numberToIPv4(base + offset);
      if (host !== prefix.address && privateIPv4(host) && !hosts.includes(host)) { hosts.push(host); }
    }
  }
  return hosts;
}
export function validMarker(value: ServiceMarker): boolean {
  return value !== null && value !== undefined && value.service === 'lanclip' && value.protocolVersion === 1 &&
    value.webPath === '/' && value.apiPath === '/api' && value.webSocketPath === '/ws' &&
    typeof value.authRequired === 'boolean' && Array.isArray(value.capabilities) &&
    value.capabilities.length <= 32 && value.capabilities.every((cap: string) => typeof cap === 'string') &&
    ['text', 'link', 'image', 'file', 'websocket', 'audit'].every((cap: string) => value.capabilities.includes(cap));
}
export function legacyPage(html: string): boolean {
  return /<title>局域网剪贴板\s*\|\s*LanClip<\/title>/.test(html) &&
    /<div[^>]+id=["']root["']/.test(html) && html.includes('/lanclip-logo.png') &&
    /<script[^>]+type=["']module["']/.test(html);
}
export function safeAssetPath(path: string): string {
  // Preserve the server's existing query, but reject any alternate origin or encoded traversal.
  const plain = path.split('?')[0];
  if (!/^\/api\/assets\/[^/?#]+\/download$/.test(plain) && !/^\/assets\/[A-Za-z0-9_./%~-]+$/.test(plain)) {
    throw new Error('服务返回了不受支持的附件地址');
  }
  const decoded = decodeURIComponent(plain);
  if (decoded.includes('..') || decoded.includes('\\') || path.includes('#') || /[\r\n]/.test(path)) {
    throw new Error('附件地址无效');
  }
  return path;
}
export function safeFilename(name: string): string {
  return name.replace(/[\\/\x00-\x1f<>:"|?*]/g, '_').slice(0, 180) || 'LanClip-file';
}
export function formatBytes(bytes: number): string {
  if (bytes >= 1048576) { return `${(bytes / 1048576).toFixed(1)} MB`; }
  if (bytes >= 1024) { return `${(bytes / 1024).toFixed(1)} KB`; }
  return `${bytes} B`;
}
