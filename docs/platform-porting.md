# Android 与 HarmonyOS 移植说明

## 平台选择

- Android：Kotlin + Jetpack Compose + Android BLE GATT。学校登录使用限制域名的 WebView；U净短信登录和设备查询走独立 HTTPS 客户端。
- HarmonyOS NEXT：ArkTS + ArkUI + `@kit.ConnectivityKit` BLE API + ArkWeb。Android Java BLE 和 iOS CoreBluetooth 不能直接复用。
- `Sources/WaterCore` 的 Swift 代码不能直接链接进 Kotlin/ArkTS。帧结构、签名编码、请求字段和会话状态机需要逐项移植，并以同一组脱敏样例核对。

## Android 必需能力

- Android 12/API 31 起，BLE 扫描与连接分别申请 `BLUETOOTH_SCAN`、`BLUETOOTH_CONNECT` 运行时权限；旧版权限按官方文档限制到 API 30。无需位置推断时才可声明 `neverForLocation`，并需验证目标水控广播没有因此被过滤。
- GATT 生命周期必须处理扫描/连接超时、服务发现、订阅 FFE1 通知、FFE2 带响应写入、分片帧重组、异常断连和资源释放。
- 校园/U净 token、热水账户信息和未决交易记录应使用 Android Keystore 支持的本机加密存储；不得放入可导出的备份或日志。未决交易恢复不得自动重发请求。
- 相机二维码仅接受 `https://q.ujing.com.cn/ucqrc/index.html` 且仅一个 18 位 `cd` 参数；扫描后只查设备信息，不直接加载二维码网址。

## HarmonyOS NEXT 必需能力

- 使用 ArkTS/ArkUI 项目模板和当前 SDK，不采用旧 HarmonyOS Java/FA 项目示例。
- BLE 需使用当前 Connectivity Kit BLE API，声明并经真机批准 `ohos.permission.ACCESS_BLUETOOTH`；按系统要求处理附近设备权限与蓝牙开关状态。
- 学校官方认证页只允许 CAS、校园门户和一卡通 HTTPS 主机。只有用户点击“读取登录结果”后，才从一卡通页面读取会话存储；不得把校园密码发送给应用接口。
- ArkWeb 预览器不支持完整 Web 页面效果，必须用模拟器或真机验证登录和 `localStorage` 读取。
- Android 的 APK 签名与 Harmony 的 HAP/APP 签名流程不同；Harmony 真机安装还要求 DevEco 调试签名及设备授权。

## 安全和发行边界

本机 iOS 生成器只会在 Debug 配置且本机存在 `private/distribution/WaterPlatformProfile.json` 时复制该资源；Debug App 可被提取出其中参数，不得分发。Release IPA 不带该资源，首次设置热水仍需本人合法取得的平台参数。公开源码与 Release 资产不得包含 `private/`、账号信息、共享参数或签名材料。

Android 测试包也不内置平台参数。开发者可以使用 `tools/provision-android-water.py` 将仅含平台字段的本机文件暂存到指定 Debug 测试设备；App 会在本机加密并消费一次性文件。该脚本不应对 Release 包或他人设备使用。HarmonyOS 尚未实现；若后续移植，身份与平台参数仍须按用户授权在设备端处理。

如果要让全新用户无需自己取得热水平台参数，需要设计服务端签名代理或取消客户端共享密钥依赖；不能靠混淆或把共享密钥放进 APK/IPA 解决。

Android/Harmony 构建需由各自 SDK 编译、签名和真机运行。没有编译器产物、设备日志和实机结果时，源代码检查不等于支持已验证。

## 官方资料（2026-10-23 查阅）

- [Android BLE 权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [Android GATT 连接](https://developer.android.com/develop/connectivity/bluetooth/ble/connect-gatt-server)
- [Jetpack Compose 快速开始](https://developer.android.com/develop/ui/compose/setup)
- [HarmonyOS ArkTS 开发指引](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/arkts-get-started-V5)
- [HarmonyOS BLE 官方 Codelab](https://developer.huawei.com/consumer/en/codelab/HarmonyOS-BLE/)
- [HarmonyOS WebView/ArkWeb Codelab](https://developer.huawei.com/consumer/en/codelab/HarmonyOS-WebView/)
- [DevEco 真机运行和调试签名步骤](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-hmos-run-device)


2026-10-29 本地候选选择直接分发共用平台配置，换取无需自建云服务和首次手动导入；这并未消除提取风险。构建仅从本地文件注入通用字段，不复制个人身份。现场验收和发布状态见 [Beta 2 候选](release-0.8.0-beta.2.md)。
