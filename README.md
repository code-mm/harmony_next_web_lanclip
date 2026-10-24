# LanClip · HarmonyOS NEXT

**原生发现/连接页 + ArkWeb Web 嵌套现有服务网页**，与 Android 客户端保持同一架构。

网页登录、文本/链接/图片/文件、删除、设备名称、审计和 WebSocket 实时同步全部由现有网页实现。App 不重写这些业务，也不把网页业务源码打包进 HAP；网页更新后两端直接加载新网页。

## 构建和安装

包名 `com.codemm.lanclip`，版本 `1.0.0 / code 1`。声明 HarmonyOS 5.0.5 / API 17 起；本轮实际构建 SDK 26.0.0.105，设备验收为专用 HarmonyOS 7 / API 26 模拟器，未声称 API 17 真机通过。

使用官方 DevEco Studio/SDK、DevEco CLI 1.3.9、Node.js 22.19.0：

```sh
./scripts/check.sh
```

也可以分别运行：

```sh
node --disable-warning=ExperimentalWarning --test tests/policy.test.mjs
devecocli check arkts
devecocli check lint
devecocli build --assemble-type assembleHap
```

若 CLI 不在 PATH，设置 `DEVECOCLI=/绝对路径/devecocli`。输出 `entry/build/default/outputs/default/entry-default-unsigned.hap`。这是未签名开发 HAP，已在本轮专用模拟器安装；真机需在 DevEco Studio 为本应用配置合法 Debug 签名重新构建。仓库不含签名材料。

```sh
devecocli device list --format json
devecocli run --skip-build --device '<明确选择的序列号>'
shasum -a 256 entry/build/default/outputs/default/entry-default-unsigned.hap
```

## 使用

1. 与 LanClip 服务连接同一 Wi-Fi / 以太网，点击扫描，或输入完整本地服务地址。默认端口 9000、9001，可添加已知端口。
2. 验证公开服务标识后进入该服务原网页；密码在网页中填写。
3. 网页文件输入调用鸿蒙系统选择器，下载使用认证 URL/现有查询参数和系统保存选择器。原生“粘贴”只在用户点击时向当前主页面发送粘贴事件，处理局域网 HTTP 的剪贴板限制。
4. “发现”暂时隐藏同一个 Web 实例，“回到网页”保留页面状态。Web 的 DOM storage/Cookie 按 origin 保存网页会话；切换服务不会把原服务密码交给新服务。

## 原生部分的范围

- 当前真实网络前缀内有限探测、mDNS 候选校验、手动地址、最近地址、取消及重试。
- ArkWeb JavaScript / DOM storage、原生返回/刷新、外链系统浏览器、系统栏和键盘 resize。
- 系统照片/文档选择器、流式附件保存、主动文本/图片粘贴。
- 没有原生登录、内容 CRUD、上传、审计或 WebSocket 业务实现。

只声明 INTERNET、GET_NETWORK_INFO。系统选择器授权所选文件；PasteButton 为当次操作授权剪贴板读取，不后台同步。无通用 JS bridge、任意本地文件访问、SSL 错误绕过；外部页面/资源不能取得当前服务的平台能力。Debug 包可通过本机转发检查网页，Release 根据应用 debug 标志关闭此能力。

## 云端状态和验证

已优先尝试 GitHub 云端工作流，当前 OAuth App 缺 `workflow` 权限，GitHub 明确拒绝接收工作流，云端构建未执行。本轮使用本机已有官方 SDK 完成真实构建和设备验收。未更换凭据或绕过权限。

云端模板位于 [docs/ci/harmony.yml.example](docs/ci/harmony.yml.example)，尚未执行。将来启用需要 workflow 写入权限及官方 Linux CLT 下载地址/SHA（模板仓库变量说明）。

[协议与平台边界](docs/protocol.md) · [本轮实际验收记录](docs/acceptance.md)

API 17 真机、家庭 Wi-Fi/mDNS、平板/折叠/横屏、多选和大文件/故障矩阵仍需分别验证。系统文档选择每次最多 10 个；主动图片粘贴限制编码 8 MB/32M 像素，较大图片使用网页文件选择器；流式下载上限 4 GB/10 分钟，未做 4 GB 实机验收。没有使用原生重写版的测试冒充 ArkWeb 结果。

本轮不涉及 Android APK 版本/双源更新、HarmonyOS 正式签名、公开 Release 或应用市场提交。

## 本轮制品

`1.0.0 / code 1`，未签名开发 HAP，164,095 字节。

```text
SHA-256 128ac10250b7263df509b84e302f45c573a03c98f142d87ed93c9fd02e7b6c7c
```
