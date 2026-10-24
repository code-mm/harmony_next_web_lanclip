import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { FoundService, Discovery, localNetwork } from '../network/Discovery';
import { WebFiles } from '../network/WebFiles';
import { normalizeOrigin, parsePorts, safeAssetPath, safeFilename, hostAllowed, originHost } from '../model/Protocol';

interface PopupVisibility { isVisible: boolean; }

@Entry
@Component
struct Index {
  @StorageLink('foreground') @Watch('foregroundChanged') foreground: boolean = true;
  @State address: string = '';
  @State ports: string = '9000,9001';
  @State history: string[] = [];
  @State services: FoundService[] = [];
  @State scanning: boolean = false;
  @State busy: boolean = false;
  @State scanStatus: string = 'LanClip · 仅扫描当前 Wi-Fi / 以太网';
  @State notice: string = '';
  @State origin: string = '';
  @State showWeb: boolean = false;
  @State loading: boolean = false;
  @State manualOpen: boolean = false;
  @State portsOpen: boolean = false;
  @State menuOpen: boolean = false;
  @State wide: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private files: WebFiles = new WebFiles();
  private discovery: Discovery = new Discovery();
  private prefs?: preferences.Preferences;
  private generation: number = 0;
  private scanGeneration: number = 0;
  private networkGeneration: number = 0;
  private networkKey: string = '';
  private networkTimer: number = -1;

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void {
    // Remote inspection is available only in Debug packages, never enabled for Release.
    webview.WebviewController.setWebDebuggingAccess(this.context().applicationInfo.debug);
    preferences.getPreferences(this.context(), { name: 'lanclip-arkweb' }).then((prefs: preferences.Preferences) => {
      this.prefs = prefs; this.ports = prefs.getSync('ports', '9000,9001') as string;
      try { this.history = JSON.parse(prefs.getSync('history', '[]') as string) as string[]; } catch (_) {}
      if (this.foreground) { this.scan(); }
    }).catch(() => { this.notice = '本地设置暂不可用，仍可手动连接'; });
  }
  aboutToDisappear(): void { this.generation++; this.scanGeneration++; this.discovery.stop(); this.files.cancel(); clearInterval(this.networkTimer); }
  private foregroundChanged(): void {
    if (!this.foreground) { this.stopScan(); }
    else if (this.origin) {
      localNetwork().then((network) => { if (network.key !== this.networkKey) { this.leaveService('网络已变化，请重新验证服务'); } }).catch(() => this.leaveService('网络不可用，请重新连接'));
    }
  }
  private async remember(): Promise<void> {
    await this.prefs?.put('ports', this.ports); await this.prefs?.put('history', JSON.stringify(this.history)); await this.prefs?.flush();
  }
  private async perform(action: () => Promise<void>): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.notice = '';
    try { await action(); } catch (error) { this.notice = (error as Error).message || '操作失败，请重试'; } finally { this.busy = false; }
  }
  private stopScan(): void { this.scanGeneration++; this.discovery.stop(); this.scanning = false; }
  private scan(): void {
    if (this.scanning) { this.stopScan(); this.scanStatus = '扫描已取消'; return; }
    let ports: number[];
    try { ports = parsePorts(this.ports); } catch (error) { this.notice = (error as Error).message; return; }
    const generation = ++this.scanGeneration;
    this.scanning = true; this.services = []; this.notice = ''; this.scanStatus = '正在发现服务…'; this.remember().catch(() => {});
    this.discovery.scan(this.context(), ports, this.history,
      (service: FoundService) => { if (generation === this.scanGeneration) { this.services = this.services.concat([service]); } },
      (status: string) => { if (generation === this.scanGeneration) { this.scanStatus = status; } })
      .catch((error: Error) => { if (generation === this.scanGeneration) { this.notice = error.message; } })
      .finally(() => { if (generation === this.scanGeneration) { this.scanning = false; } });
  }
  private sameOrigin(address: string): boolean {
    const match = /^https?:\/\/[^/?#]+/.exec(address);
    try { return !!match && normalizeOrigin(match[0]) === this.origin; } catch (_) { return false; }
  }
  private trusted(): boolean {
    try { return this.foreground && this.showWeb && this.sameOrigin(this.controller.getUrl()); } catch (_) { return false; }
  }
  private resourceAllowed(address: string): boolean {
    return address === 'about:blank' || this.sameOrigin(address.replace(/^ws/, 'http')) ||
      address.startsWith('blob:') && this.sameOrigin(address.slice(5)) || /^data:image\/(png|jpeg|gif|webp);/i.test(address);
  }
  private async connect(): Promise<void> {
    this.stopScan(); const generation = ++this.generation;
    const network = await localNetwork();
    const service = await this.discovery.verify(this.address, network);
    if (generation !== this.generation) { return; }
    const previous = this.origin;
    this.origin = service.origin; this.networkKey = network.key; this.showWeb = true; this.notice = '';
    if (previous && previous !== service.origin) { this.files.cancel(); this.controller.loadUrl(`${service.origin}/`); }
    this.history = [service.origin].concat(this.history.filter((origin: string) => origin !== service.origin)).slice(0, 8);
    await this.remember(); clearInterval(this.networkTimer);
    const watch = ++this.networkGeneration;
    this.networkTimer = setInterval(() => {
      localNetwork().then((current) => {
        if (watch !== this.networkGeneration) { return; }
        if (current.key !== this.networkKey) { this.leaveService('网络已切换，请重新验证服务'); }
      }).catch(() => { if (watch === this.networkGeneration) { this.leaveService('网络不可用，请重新连接'); } });
    }, 1500);
  }
  private leaveService(message: string = ''): void {
    this.generation++; this.networkGeneration++; this.stopScan(); this.files.cancel(); clearInterval(this.networkTimer);
    try { this.controller.stop(); this.controller.loadUrl('about:blank'); } catch (_) {}
    this.origin = ''; this.showWeb = false; this.notice = message;
    this.controller = new webview.WebviewController();
  }
  private browseServices(): void { this.showWeb = false; this.notice = ''; }
  private openService(origin: string): void { this.address = origin; this.perform(() => this.connect()); }
  private recentOrigins(): string[] { return this.history.filter((origin: string) => !this.services.some((service: FoundService) => service.origin === origin)); }
  private async copySelection(): Promise<void> {
    if (!this.trusted()) { throw new Error('请先打开服务网页并选中文本'); }
    const value = await this.controller.runJavaScript('window.getSelection()?.toString() || ""');
    const text = JSON.parse(value) as string;
    if (!text) { throw new Error('请先在网页选中文本'); }
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
    this.notice = '已复制选中文本';
  }
  private async external(address: string): Promise<void> {
    if (!/^https?:\/\//i.test(address)) { return; }
    await this.context().openLink(address);
  }
  private navigation(request: WebResourceRequest): boolean {
    const address = request.getRequestUrl();
    if (address === 'about:blank') { return false; }
    if (this.sameOrigin(address)) {
      const path = address.slice(address.indexOf('/', address.indexOf('://') + 3));
      if (/^\/api\/assets\/[^/?#]+\/download(?:\?|$)/.test(path) && request.isMainFrame()) {
        this.perform(() => this.download(address, 'LanClip-file')); return true;
      }
      return false;
    }
    if (request.isMainFrame() && request.isRequestGesture()) { this.external(address).catch(() => { this.notice = '无法打开外部链接'; }); }
    return true;
  }
  private async download(address: string, suggested: string): Promise<void> {
    if (!this.trusted() || !this.sameOrigin(address)) { throw new Error('仅允许保存当前服务的附件'); }
    const network = await localNetwork();
    if (network.key !== this.networkKey || !hostAllowed(originHost(this.origin), network.prefixes)) { throw new Error('网络已变化，请重新连接'); }
    const match = /^https?:\/\/[^/?#]+(\/.*)$/.exec(address);
    if (!match) { throw new Error('附件地址无效'); } safeAssetPath(match[1]);
    const cookie = webview.WebCookieManager.getCookie(address);
    const name = safeFilename(suggested || 'LanClip-file');
    const saved = await this.files.save(this.context(), address, name, cookie, (text: string) => { this.notice = text; });
    this.notice = saved ? '已保存到所选位置' : '已取消保存';
  }
  private fileSelector(event: OnShowFileSelectorEvent): boolean {
    const generation = this.generation;
    if (!this.trusted()) { event.result.handleFileList([]); return true; }
    const accept = event.fileSelector.getAcceptType();
    const images = accept.length > 0 && accept.every((type: string) => type.startsWith('image/'));
    this.files.choose(this.context(), images, event.fileSelector.getMode() === FileSelectorMode.FileOpenMultipleMode)
      .then((uris: string[]) => { event.result.handleFileList(generation === this.generation && this.showWeb && this.sameOrigin(this.controller.getUrl()) ? uris : []); })
      .catch(() => event.result.handleFileList([]));
    return true;
  }
  private async paste(): Promise<void> {
    if (!this.trusted()) { throw new Error('请先打开已验证的服务网页'); }
    const generation = this.generation;
    const data = await pasteboard.getSystemPasteboard().getData();
    let payload: string;
    if (data.getPrimaryText()) {
      payload = `dt.setData('text/plain',${JSON.stringify(data.getPrimaryText())});`;
    } else if (data.hasType(pasteboard.MIMETYPE_PIXELMAP)) {
      const pixel = data.getPrimaryPixelMap(); const packer = image.createImagePacker();
      try {
        const info = await pixel.getImageInfo(); if (info.size.width * info.size.height > 32 * 1024 * 1024) { throw new Error('图片过大，请用网页文件选择器上传'); }
        const bytes = await packer.packing(pixel, { format: 'image/png', quality: 100 });
        if (bytes.byteLength > 8 * 1024 * 1024) { throw new Error('图片过大，请用网页文件选择器上传'); }
        const b64 = new util.Base64Helper().encodeToString(new Uint8Array(bytes));
        payload = `dt.items.add(new File([Uint8Array.from(atob(${JSON.stringify(b64)}),c=>c.charCodeAt(0))],'clipboard.png',{type:'image/png'}));`;
      } finally { await packer.release(); await pixel.release(); }
    } else { throw new Error('剪贴板没有可用的文本或图片'); }
    if (generation !== this.generation || !this.trusted()) { throw new Error('服务已切换，粘贴已取消'); }
    // Native user action -> main frame JS only. No JavaScript-to-native bridge is registered.
    await this.controller.runJavaScript(`(()=>{if(window!==top||location.origin!==new URL(${JSON.stringify(this.origin)}).origin)return;const dt=new DataTransfer();${payload}const a=document.activeElement;if(dt.files.length===0&&(a instanceof HTMLTextAreaElement||a instanceof HTMLInputElement)){const p=a instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(p,'value').set.call(a,dt.getData('text/plain'));a.dispatchEvent(new Event('input',{bubbles:true}));return;}const box=document.querySelector('main section[tabindex]');if(box)box.dispatchEvent(new ClipboardEvent('paste',{clipboardData:dt,bubbles:true,cancelable:true}));})()`);
  }

  @Builder
  introduction() {
    Column({ space: 12 }) {
      Text('选择剪贴板服务').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#303238').width('100%')
      Text('连接同一局域网，选择服务开始共享').fontSize(16).fontColor('#303238').width('100%')
      Stack() {
        Image($r('app.media.radar')).width(144).height(144)
        Image($r('app.media.radar_sweep')).width(144).height(144)
          .rotate({ angle: this.scanning ? 360 : 0 })
          .animation({ duration: this.scanning ? 3600 : 0, iterations: this.scanning ? -1 : 1, curve: Curve.Linear })
          .opacity(this.scanning ? 1 : 0)
        Image($r('app.media.lanclip')).width(40).height(40)
      }.width('100%').height(144).accessibilityLevel('no')
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 16, right: 16, top: 18, bottom: 12 })
      .backgroundColor(Color.White).borderRadius(16).margin({ bottom: 12 })
  }
  @Builder
  serviceCard(origin: string, verified: boolean) {
    Row({ space: 8 }) {
      Image($r('app.media.lanclip')).width(40).height(40).accessibilityLevel('no')
      Column({ space: 2 }) {
        Text('LanClip').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#303238').width('100%')
        Text(origin.replace(/^https?:\/\//, '')).fontSize(13).fontColor('#303238').width('100%')
        Text(verified ? '已验证' : '需重新验证').fontSize(12).fontColor(verified ? '#2E6450' : '#65686E').width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('连接', { type: ButtonType.Normal }).id(`${verified ? 'service' : 'recent'}-${origin}`)
        .fontSize(14).fontColor(Color.White).backgroundColor('#36383D').borderRadius(12)
        .constraintSize({ minWidth: 64, minHeight: 48 }).padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .enabled(!this.busy).onClick(() => this.openService(origin))
    }.width('100%').constraintSize({ minHeight: 88 }).padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(Color.White).borderRadius(16).margin({ bottom: 12 })
  }
  @Builder
  discoveredServices() {
    Column() {
      Text(`发现 ${this.services.length} 个服务`).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#303238')
        .width('100%').padding({ top: 6, bottom: 12 })
      ForEach(this.services, (service: FoundService) => { this.serviceCard(service.origin, true) }, (service: FoundService) => service.origin)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  scanActions() {
    Column({ space: 8 }) {
      Button(this.scanning ? '停止扫描' : '扫描服务', { type: ButtonType.Normal }).id('scan-button')
        .width('100%').constraintSize({ minHeight: 48 }).fontSize(16).fontColor(Color.White)
        .backgroundColor('#36383D').borderRadius(12).padding({ top: 8, bottom: 8 }).enabled(!this.busy).onClick(() => this.scan())
      Button('手动连接', { type: ButtonType.Normal }).id('manual-button').width('100%').constraintSize({ minHeight: 48 })
        .fontSize(16).fontColor('#36383D').backgroundColor(Color.Transparent).borderRadius(12)
        .onClick(() => { this.manualOpen = !this.manualOpen; })
      if (this.manualOpen) { this.manualConnection() }
    }.width('100%').margin({ bottom: 12 })
  }
  @Builder
  manualConnection() {
    Column({ space: 10 }) {
      Text('手动连接').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#303238').width('100%')
      TextInput({ text: this.address, placeholder: 'http://主机:端口' }).id('address-input').height(48)
        .fontSize(16).fontColor('#303238').backgroundColor('#F4F5F7').borderRadius(8)
        .onChange((text: string) => { this.address = text; })
      Button('验证并连接', { type: ButtonType.Normal }).id('connect-button').width('100%').constraintSize({ minHeight: 48 })
        .fontSize(16).fontColor(Color.White).backgroundColor('#36383D').borderRadius(12)
        .enabled(!this.busy && this.address.trim().length > 0).onClick(() => this.perform(() => this.connect()))
      Button('额外端口设置', { type: ButtonType.Normal }).id('ports-toggle').width('100%').height(48)
        .fontSize(16).fontColor('#36383D').backgroundColor(Color.Transparent).onClick(() => { this.portsOpen = !this.portsOpen; })
      if (this.portsOpen) {
        TextInput({ text: this.ports, placeholder: '探测端口，逗号分隔' }).id('ports-input').height(48)
          .onChange((text: string) => { this.ports = text; }).enabled(!this.scanning)
        Button('保存端口并扫描', { type: ButtonType.Normal }).width('100%').height(48).fontSize(16)
          .fontColor(Color.White).backgroundColor('#36383D').borderRadius(12).enabled(!this.busy && !this.scanning).onClick(() => this.scan())
      }
    }.width('100%').padding(16).backgroundColor(Color.White).borderRadius(16)
  }
  @Builder
  recentServices() {
    if (this.recentOrigins().length > 0) {
      Column() {
        Text('最近成功连接').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#303238')
          .width('100%').padding({ top: 6, bottom: 12 })
        ForEach(this.recentOrigins(), (origin: string) => { this.serviceCard(origin, false) }, (origin: string) => origin)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }
  @Builder
  discoveryPage() {
    Scroll() {
      Column() {
        if (this.wide) {
          Row({ space: 16 }) {
            Column() { this.introduction(); this.scanActions() }.layoutWeight(0.9)
            Column() { this.discoveredServices(); this.recentServices() }.layoutWeight(1.3)
          }.alignItems(VerticalAlign.Top).width('100%')
        } else {
          this.introduction()
          this.discoveredServices()
          this.scanActions()
          this.recentServices()
        }
      }.width('100%').constraintSize({ maxWidth: 1120 }).padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
    }.align(Alignment.Top).width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area) => { this.wide = Number(area.width) >= 720; })
      .visibility(this.showWeb ? Visibility.Hidden : Visibility.Visible)
  }
  @Builder
  moreMenu() {
    Column({ space: 2 }) {
      Button('刷新', { type: ButtonType.Normal }).width('100%').height(44).fontSize(16).fontColor('#36383D').backgroundColor(Color.Transparent)
        .onClick(() => { this.menuOpen = false; if (this.showWeb) { this.controller.refresh(); } else if (!this.scanning) { this.scan(); } })
      Button('切换服务', { type: ButtonType.Normal }).width('100%').height(44).fontSize(16).fontColor('#36383D').backgroundColor(Color.Transparent)
        .onClick(() => { this.menuOpen = false; this.browseServices(); })
      if (this.showWeb) {
        PasteButton().id('native-paste').height(44).width('100%').fontColor('#36383D').iconColor('#36383D').backgroundColor(Color.White)
          .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
            this.menuOpen = false;
            if (result === PasteButtonOnClickResult.SUCCESS) { this.perform(() => this.paste()); }
          })
        Button('复制选中', { type: ButtonType.Normal }).width('100%').height(44).fontSize(16).fontColor('#36383D').backgroundColor(Color.Transparent)
          .onClick(() => { this.menuOpen = false; this.perform(() => this.copySelection()); })
      }
      Button('取消任务', { type: ButtonType.Normal }).width('100%').height(44).fontSize(16).fontColor('#36383D').backgroundColor(Color.Transparent)
        .onClick(() => { this.menuOpen = false; this.files.cancel(); this.generation++; this.stopScan(); this.notice = '任务已取消，可重新扫描'; })
    }.width(184).padding(8).backgroundColor(Color.White)
  }

  build() {
    Column() {
      Row() {
        if (this.showWeb) {
          Button({ type: ButtonType.Circle }) { Image($r('app.media.header_back')).width(24).height(24) }
            .id('back-button').width(48).height(48).backgroundColor(Color.Transparent).accessibilityText('返回').onClick(() => {
            if (this.controller.accessBackward()) { this.controller.backward(); } else { this.browseServices(); }
          })
        }
        Text('LanClip').fontSize(22).fontWeight(FontWeight.Medium).fontColor('#252D38').layoutWeight(1).maxLines(1).padding({ left: 8, right: 8 })
        Button({ type: ButtonType.Circle }) { Image($r('app.media.header_home')).width(24).height(24) }
          .id('discovery-button').width(48).height(48).backgroundColor(Color.Transparent).accessibilityText('发现服务').onClick(() => this.browseServices())
        Button({ type: ButtonType.Circle }) { Image($r('app.media.header_refresh')).width(24).height(24) }
          .id('refresh-button').width(48).height(48).backgroundColor(Color.Transparent).accessibilityText('刷新')
          .onClick(() => { if (this.showWeb) { this.controller.refresh(); } else if (!this.scanning) { this.scan(); } })
        Button({ type: ButtonType.Circle }) { Image($r('app.media.header_more')).width(24).height(24) }
          .id('more-button').width(48).height(48).backgroundColor(Color.Transparent).accessibilityText('更多')
          .onClick(() => { this.menuOpen = !this.menuOpen; })
          .bindPopup(this.menuOpen, { builder: this.moreMenu, placement: Placement.BottomRight,
            onStateChange: (event: PopupVisibility) => { this.menuOpen = event.isVisible; } })
      }.width('100%').height(56).padding({ left: 8, right: 8 }).backgroundColor('#F4F5F7')
      if (this.showWeb) {
        Row({ space: 10 }) {
          Image($r('app.media.header_link')).width(20).height(20).accessibilityLevel('no')
          Text(this.origin).fontSize(14).fontColor('#667085').layoutWeight(1).maxLines(2).copyOption(CopyOptions.LocalDevice)
        }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 8 })
      }
      Text(this.showWeb ? '服务已验证 · LanClip' : this.scanStatus).id('scan-status').fontSize(14).fontColor('#45464A')
        .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
      if (!this.showWeb && this.origin) {
        Button('回到网页', { type: ButtonType.Normal }).id('resume-web').height(36).fontSize(14).fontColor('#36383D')
          .backgroundColor(Color.Transparent).onClick(() => { this.showWeb = true; this.notice = ''; })
      }
      if (this.notice) { Text(this.notice).id('notice').fontSize(13).fontColor('#8C4E20').padding(12).backgroundColor('#FFF1DC').width('100%') }
      if (this.busy) {
        Row({ space: 10 }) {
          LoadingProgress().width(22).height(22).color('#167A70')
          Text('正在处理…').layoutWeight(1).fontSize(13)
          Button('取消').height(32).fontSize(13).onClick(() => { this.files.cancel(); this.generation++; this.stopScan(); })
        }.padding(10).width('100%')
      }
      Stack() {
        this.discoveryPage()
        if (this.origin) {
          Web({ src: `${this.origin}/`, controller: this.controller })
            .id('lanclip-web').width('100%').height('100%').visibility(this.showWeb ? Visibility.Visible : Visibility.Hidden)
            .javaScriptAccess(true).domStorageAccess(true).fileAccess(false).mixedMode(MixedMode.None).multiWindowAccess(false)
            .onPageBegin(() => { this.loading = true; })
            .onPageEnd(() => { this.loading = false; })
            .onLoadIntercept((event: OnLoadInterceptEvent): boolean => this.navigation(event.data))
            .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse => {
              if (this.resourceAllowed(event.request.getRequestUrl())) { return null!; }
              const response = new WebResourceResponse(); response.setResponseCode(403); response.setResponseData(''); response.setResponseMimeType('text/plain'); return response;
            })
            .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => this.fileSelector(event))
            .onDownloadStart((event: OnDownloadStartEvent) => {
              let name = 'LanClip-file';
              const match = /filename\*?=(?:UTF-8'')?"?([^";]+)/i.exec(event.contentDisposition);
              if (match) { try { name = decodeURIComponent(match[1]); } catch (_) {} }
              this.perform(() => this.download(event.url, name));
            })
            .onPermissionRequest((event: OnPermissionRequestEvent) => event.request.deny())
            .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => { event.handler.handleCancel(); this.notice = '证书校验失败，已取消加载'; })
        }
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F5F7')
  }
  onBackPress(): boolean {
    if (this.showWeb) { if (this.controller.accessBackward()) { this.controller.backward(); } else { this.browseServices(); } return true; }
    if (this.scanning) { this.stopScan(); this.scanStatus = '扫描已取消'; return true; }
    return false;
  }
}
