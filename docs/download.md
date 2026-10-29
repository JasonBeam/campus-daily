# 下载与安装

先在[下载页](https://jasonbeam.github.io/campus-daily/)选择设备，或从 [Beta 2 Release](https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0-beta.2)下载对应安装包。校日常仍为测试版。

## Android

[下载 Android 0.2.0-alpha22 APK](https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.2/campus-daily-android-0.2.0-alpha22-debug.apk) · [SHA-256 校验文件](https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.2/SHA256SUMS.txt)

1. 下载 APK 并打开文件。
2. 如果系统提示，允许当前浏览器或文件管理器安装应用，然后确认安装。
3. 打开校日常，使用本人的学校账号登录。

目标系统为 Android 6.0 或更新版本。HarmonyOS 4.2 是兼容目标之一；本次发布不代表所有 Android 或鸿蒙机型都已完成实机验收。首次使用不需要开发者证书；APK 中的通用热水平台参数可以被提取。

## iPhone

[下载 iPhone 0.8.0 build 36 无签名 IPA](https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.2/CampusDaily-0.8.0-build36-unsigned.ipa) · [SHA-256 校验文件](https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.2/SHA256SUMS.txt)

IPA 需要使用你自己的 Apple 账号签名后才能安装。**Safari 下载 IPA 不会直接安装 App**，当前版本没有 TestFlight 或网页直装。免费 Personal Team 签名通常约 7 天后需要重新签名。具体步骤见[构建与签名](build-and-signing.md)。

目标系统为 iOS 17 或更新版本。iOS 小组件只在已安装并登录的 App 中有可用数据；其他签名团队下的小组件仍需单独验证。

## 第一次使用

1. 打开学校登录页面，使用本人账号完成官方登录。
2. 校日常读取校园卡与门户登记的宿舍地址；请核对页面显示的宿舍。
3. App 按校园目录自动匹配电表。目录中有同名公寓时，按提示确认一次位置；信息缺失或查询失败时可手动选择。
4. 热水配置会核验本人身份与宿舍。Android 可在“连接检查与设备信息”只读核对附近水控编号。
5. 洗衣功能使用本人的 U 净账号登录，再扫描或从照片识别洗衣机二维码。

真实热水授权、出水、结算尚未完成本轮验收，实际操作可能连接水控并产生费用。请本人到现场核对设备和官方结果；状态不明确时不要重复开始或结算。

更详细的操作见[配置教程](configuration.md)、[首次接入说明](hot-water-access.md)、[AI 使用教程](ai-guide.md)和[故障排查](troubleshooting.md)。不要公开密码、验证码、校园令牌、学号、宿舍信息、设备二维码或交易链接。
