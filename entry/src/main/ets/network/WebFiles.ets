import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { safeFilename } from '../model/Protocol';

// Platform integration only: the service's own webpage still owns all business API calls.
export class WebFiles {
  private session?: rcp.Session;
  private generation: number = 0;
  cancel(): void {
    this.generation++;
    try { this.session?.cancel(); } catch (_) {}
  }
  async choose(context: common.UIAbilityContext, images: boolean, multiple: boolean): Promise<string[]> {
    if (images) {
      const options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE; options.maxSelectNumber = multiple ? 10 : 1;
      return (await new picker.PhotoViewPicker(context).select(options)).photoUris;
    }
    const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = multiple ? 10 : 1;
    return new picker.DocumentViewPicker(context).select(options);
  }
  async save(context: common.UIAbilityContext, address: string, name: string, cookie: string,
    progress: (message: string) => void): Promise<boolean> {
    const generation = this.generation;
    const cache = `${context.cacheDir}/lanclip-${Date.now()}.part`;
    const file = await fileIo.open(cache, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    const session = rcp.createSession({ requestConfiguration: {
      transfer: { autoRedirect: false, timeout: { connectMs: 5000, transferMs: 600000, inactivityMs: 15000 } },
      proxy: 'no-proxy', security: { remoteValidation: 'system' }
    } });
    this.session = session;
    let received = 0;
    let lastProgress = 0;
    const headers: Record<string, string> = {};
    if (cookie) { headers['Cookie'] = cookie; }
    const request = new rcp.Request(address, 'GET', headers);
    request.destination = async (chunk: ArrayBuffer): Promise<void> => {
      if (generation !== this.generation) { throw new Error('下载已取消'); }
      received += chunk.byteLength;
      if (received > 4 * 1024 * 1024 * 1024) { session.cancel(); throw new Error('文件超过 4 GB'); }
      let written = 0;
      while (written < chunk.byteLength) {
        const count = await fileIo.write(file.fd, chunk.slice(written));
        if (count <= 0) { throw new Error('文件写入未完成'); } written += count;
      }
      if (Date.now() - lastProgress > 400) { progress(`正在保存 · ${(received / 1048576).toFixed(1)} MB`); lastProgress = Date.now(); }
    };
    try {
      const response = await session.fetch(request);
      if (generation !== this.generation) { throw new Error('下载已取消'); }
      if (response.statusCode !== 200) { throw new Error(`下载失败（HTTP ${response.statusCode}）；未导出文件`); }
      let filename = name;
      const disposition = (response.headers['content-disposition'] || '').toString();
      const match = /filename\*?=(?:UTF-8'')?"?([^";]+)/i.exec(disposition);
      if (match) { try { filename = decodeURIComponent(match[1]); } catch (_) {} }
      const options = new picker.DocumentSaveOptions(); options.newFileNames = [safeFilename(filename)];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0 || generation !== this.generation) { return false; }
      const destination = await fileIo.open(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { await fileIo.copyFile(cache, destination.fd); } finally { await fileIo.close(destination); }
      return true;
    } finally {
      this.session = undefined; session.close(); await fileIo.close(file);
      try { await fileIo.unlink(cache); } catch (_) {}
    }
  }
}
