# LanClip · HarmonyOS NEXT

**原生发现/连接页 + ArkWeb Web 嵌套现有服务网页**，与 Android 客户端保持同一架构。

网页登录、文本/链接/图片/文件、删除、设备名称、审计和 WebSocket 实时同步全部由现有网页实现。App 不重写这些业务，也不把网页业务源码打包进 HAP；网页更新后两端直接加载新网页。

## 构建和安装

包名 `com.codemm.lanclip`，版本 `1.0.1 / code 2`。声明 HarmonyOS 5.0.5 / API 17 起；实际构建 SDK 26.0.0.105。本轮已用合法 Debug 签名在 Mate 60 Pro / HarmonyOS 7 安装，API 17 仍未验收。

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

若 CLI 不在 PATH，设置 `DEVECOCLI=/绝对路径/devecocli`。仓库默认不含签名配置，输出 `entry/build/default/outputs/default/entry-default-unsigned.hap`；真机必须使用本应用的合法签名。已授权的开发者可在本机执行以下流程，生成含目标设备的 Debug Profile：

```sh
devecocli auth login --no-prompt
devecocli signature generate --product default --type debug
devecocli build --assemble-type assembleHap
```

签名后制品为 `entry/build/default/outputs/default/entry-default-signed.hap`。签名工具会更新本机 `build-profile.json5`；不要提交其中的本机签名配置。私钥、Profile、证书、密码和设备标识不入库；公开源码保持可移植的无签名配置。Debug HAP 只用于 Profile 允许的设备，不是应用市场发布包。

```sh
devecocli device list --format json
devecocli run --skip-build --device '<明确选择的序列号>'
shasum -a 256 entry/build/default/outputs/default/entry-default-unsigned.hap
```

## 使用

1. 与 LanClip 服务连接同一 Wi-Fi / 以太网，启动时自动进行一次有限扫描；也可以点击“扫描服务”或展开“手动连接”。默认端口 9000、9001，额外设置内可修改探测端口。
2. 验证公开服务标识后进入该服务原网页；密码在网页中填写。
3. 网页文件输入调用鸿蒙系统选择器，下载使用认证 URL/现有查询参数和系统保存选择器。“更多”中的系统粘贴按钮只在用户点击时向当前主页面发送粘贴事件，处理局域网 HTTP 的剪贴板限制。
4. 顶部主页图标暂时隐藏同一个 Web 实例，“回到网页”保留页面状态。Web 的 DOM storage/Cookie 按 origin 保存网页会话；切换服务不会把原服务密码交给新服务。

发现页与 Android 现有布局对齐：灰白卡片、黄色雷达、带验证状态与连接按钮的服务行、折叠手动连接/端口设置，以及返回、主页、刷新和更多图标。系统文件选择/保存及安全粘贴仍使用鸿蒙平台控件。

## 原生部分的范围

- 当前真实网络前缀内有限探测、mDNS 候选校验、手动地址、最近地址、取消及重试。
- ArkWeb JavaScript / DOM storage、原生返回/刷新、外链系统浏览器、系统栏和键盘 resize。
- 系统照片/文档选择器、流式附件保存、主动文本/图片粘贴。
- 没有原生登录、内容 CRUD、上传、审计或 WebSocket 业务实现。

只声明 INTERNET、GET_NETWORK_INFO。系统选择器授权所选文件；PasteButton 为当次操作授权剪贴板读取，不后台同步。无通用 JS bridge、任意本地文件访问、SSL 错误绕过；外部页面/资源不能取得当前服务的平台能力。Debug 包可通过本机转发检查网页，Release 根据应用 debug 标志关闭此能力。

## 云端状态和验证

已优先尝试 GitHub 云端工作流，当前 OAuth App 缺 `workflow` 权限，GitHub 明确拒绝接收工作流，云端构建未执行。本轮使用本机已有官方 SDK 完成真实构建和设备验收。未更换凭据或绕过权限。

云端模板位于 [docs/ci/harmony.yml.example](docs/ci/harmony.yml.example)，尚未执行。将来启用需要 workflow 写入权限及官方 Linux CLT 下载地址/SHA（模板仓库变量说明）。

[协议与平台边界](docs/protocol.md) · [1.0.0 模拟器验收](docs/acceptance.md) · [1.0.1 真机与界面验收](docs/acceptance-phone-1.0.1.md)

真实 Wi-Fi 上已发现默认端口与 mDNS 非默认端口服务；原网页显示已连接。2.5 MB 合成文件通过系统选择器上传及保存，手机导出文件独立读回后的大小/SHA-256 与源文件一致。1.0.1 覆盖安装后已确认网页会话保留。逐版本验证范围见真机验收记录。

API 17、其他 Wi-Fi/路由器、平板/折叠/横屏、多选和大文件/故障矩阵仍需分别验证。系统文档选择每次最多 10 个；主动图片粘贴限制编码 8 MB/32M 像素，较大图片使用网页文件选择器；流式下载上限 4 GB/10 分钟，未做 4 GB 实机验收。

本轮不涉及 Android APK 版本/双源更新、HarmonyOS 发布签名、公开 Release 或应用市场提交。

## 本轮制品

`1.0.1 / code 2`，本机 Debug 签名 HAP，246,715 字节，仅供已授权真机调试。二进制和签名材料不发布到源码仓库。

```text
SHA-256 881a81a7f8a2cc0644f2e8667641637281593d3089a3a5604e3578fe546b0e3f
```
