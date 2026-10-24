import { util } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';

// RCP supports disabling redirects on API 17; no credentials leave the chosen origin.
export class Transport {
  private sessions: Set<rcp.Session> = new Set();

  cancel(): void {
    this.sessions.forEach((session: rcp.Session) => { session.cancel(); session.close(); });
    this.sessions.clear();
  }

  async request(url: string, token: string = '', method: rcp.HttpMethod = 'GET',
    content?: rcp.RequestContent, timeout: number = 10000, maxBytes: number = 4 * 1024 * 1024): Promise<BufferedResponse> {
    const session = rcp.createSession({ requestConfiguration: {
      transfer: { autoRedirect: false, timeout: { connectMs: Math.min(3000, timeout), transferMs: timeout } },
      proxy: 'no-proxy',
      security: { remoteValidation: 'system' }
    } });
    this.sessions.add(session);
    const headers: Record<string, string> = { 'Accept': 'application/json', 'Cache-Control': 'no-store' };
    if (token) { headers['Authorization'] = `Bearer ${token}`; }
    if (typeof content === 'string') { headers['Content-Type'] = 'application/json'; }
    const request = new rcp.Request(url, method, headers, content);
    // Bound memory while receiving, including chunked bodies without Content-Length.
    const chunks: ArrayBuffer[] = [];
    let size = 0;
    request.destination = (data: ArrayBuffer): void => {
      size += data.byteLength;
      if (size > maxBytes) { session.cancel(request); throw new Error('响应超过客户端大小限制'); }
      chunks.push(data);
    };
    try {
      const response = await session.fetch(request);
      if (response.statusCode >= 300 && response.statusCode < 400) { throw new Error('已拒绝服务重定向，请直接输入最终局域网地址'); }
      // Reconstruct a response with toString/toJSON without retaining the native session.
      const bytes = new Uint8Array(size);
      let offset = 0;
      chunks.forEach((chunk: ArrayBuffer) => { bytes.set(new Uint8Array(chunk), offset); offset += chunk.byteLength; });
      return new BufferedResponse(response.statusCode, bytes.buffer as ArrayBuffer, response.headers);
    } finally {
      if (this.sessions.delete(session)) { session.close(); }
    }
  }
}

// Only the fields used by LanClip are exposed, rather than fabricating an RCP Response.
export class BufferedResponse {
  statusCode: number;
  body: ArrayBuffer;
  headers: rcp.ResponseHeaders;
  constructor(statusCode: number, body: ArrayBuffer, headers: rcp.ResponseHeaders) { this.statusCode = statusCode; this.body = body; this.headers = headers; }
  toString(): string { return util.TextDecoder.create('utf-8', { fatal: false }).decodeWithStream(new Uint8Array(this.body)); }
  toJSON(): Object { return JSON.parse(this.toString()) as Object; }
}
