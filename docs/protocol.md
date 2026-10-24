# 服务协议与 Web 容器边界

## 发现

默认网络必须是 Wi-Fi / 以太网，拒绝蜂窝与 VPN。只接受当前真实链路前缀内的数字 RFC1918 IPv4；暂不支持 IPv6 和主机名。前缀 /24–/30 可有限遍历，最多 256 个主机、8 个端口、8 个 worker、20 秒；大子网仅 mDNS、网关和最近地址，不截成 /24。扫描可停止/重扫，网络变化和迟到回调按代次隔离。

mDNS 类型 `_lanclip._tcp`，TXT 要求 `service=lanclip`、`protocolVersion=1`、`scheme=http`；解析结果必须再通过公开 HTTP 标识验证。仅有广播名称不算服务。

`GET /.well-known/lanclip` 不带业务密码；必须 HTTP 200 / JSON，满足以下契约：

```json
{"service":"lanclip","protocolVersion":1,"webPath":"/","apiPath":"/api","webSocketPath":"/ws","authRequired":true,"capabilities":["text","link","image","file","websocket","audit"]}
```

标识 404/405 时，有限端口/手动连接可组合验证旧网页中文 title、root 容器、logo 路径和 module script；mDNS 候选不接受旧网页降级。无广播的旧服务不能凭空发现任意端口。

## 网页业务

App 只加载被选中服务的根页面。业务全部由网页自身调用原有 `/api/*` 和 `/ws`；原生不维护密码、业务模型或重复的 CRUD/审计/同步逻辑。网页原有按 origin 的 localStorage/Cookie 会话交给 ArkWeb 管理。

## 必要平台适配

- 同一个 Web 实例在发现页与网页之间保留；切换服务使用独立 origin 存储。
- 只接受同源资源、同源 blob 和受限内联图片。外链交给系统，非用户触发的异源导航不自动打开。
- 禁用任意本地文件访问；文件 input 的结果只来自系统选择器，切换服务后释放旧回调。
- 原生 PasteButton 用户主动读取文本/图片，通过当前主 frame 的 DOM 粘贴事件交给原网页；不注册 JS 到原生的通用桥，不在后台读取剪贴板。
- 附件地址仅接受当前 origin 的 `/api/assets/{id}/download` 或 `/assets/...`，保留网页生成的查询参数及 Cookie。RCP 禁止重定向，使用系统 TLS 验证，流式下载到私有临时文件，再经系统保存选择器导出；完成/失败清理临时文件，支持取消。
- 仅 INTERNET、GET_NETWORK_INFO；照片/文档/剪贴板按系统选择器与 PasteButton 的用户操作临时授权。

只安装 App 不会新增服务标识或 mDNS 广播，服务端和网页保持原有部署。模拟器验收不证明真实家庭网络、不同系统版本或全部故障分支通过。
