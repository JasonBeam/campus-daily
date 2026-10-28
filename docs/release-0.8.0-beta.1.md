# 校日常 0.8.0 Beta 1

面向广东工商职业技术大学的 iPhone 与 Android 测试版。此次更新完善校园网页登录、校园卡同步、宿舍信息读取和安卓蓝牙流程，并统一两端的日常、热水、洗衣与设备页面。

## 下载

- [Android 测试版 APK（0.2.0-alpha12）](https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.1/campus-daily-android-0.2.0-alpha12-debug.apk) · [SHA-256 校验文件](https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.1/SHA256SUMS.txt)
- [iPhone 无签名 IPA（0.8.0 build 29）](https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.1/CampusDaily-0.8.0-build29-unsigned.ipa) · [SHA-256 校验文件](https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.1/CampusDaily-0.8.0-build29-unsigned.ipa.sha256)
- [安装与配置说明](download.md) · [AI 使用教程](ai-guide.md)

Android APK 已由项目方签名，按手机提示下载并安装即可。iPhone IPA 未签名，需要使用自己的 Apple 账号签名后安装；Safari 下载不会直接安装 App。

## 更新内容

- 使用学校官方网页登录后，校日常可同步校园卡信息和门户中的宿舍地址。
- 安卓版改善学校登录、宿舍匹配、蓝牙扫描和同名水控编号确认。
- 两端统一首页余额、热水、洗衣、订单和设备页面的布局。
- 更换账号或宿舍时清理不匹配的旧绑定，避免沿用其他账户的结果。

## 已知限制

- **宿舍电表暂时不能自动匹配，请手动选择电表。**校园卡余额同步不是本版已知故障。
- 公开安装包不含作者的热水平台私有参数。首次配置热水时，需要本人合法取得对应参数。
- 本版只面向广东工商职业技术大学环境，不代表学校或相关服务方，也不保证其他学校可用。

## 检查记录

- iOS：83 项 XCTest 与 41 项 Swift Testing 通过。
- Android：35 项单元测试、5 项流程与界面测试、23 组布局场景及 lint 通过。
- Android alpha12 已在 vivo 上覆盖安装并保留原有数据。安装成功不代表所有现场流程均已验证。
- 本轮没有执行真实热水授权、出水、结算、洗衣下单或付款。涉及实际设备和交易的结果，请以现场设备及官方页面为准。

## 隐私

请只使用本人账号。不要在 Issue、评论或 AI 对话中公开密码、验证码、Cookie、校园令牌、手机号、学号、宿舍信息、设备二维码或付款链接。
