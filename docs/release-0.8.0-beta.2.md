# 校日常 0.8.0 Beta 2

Beta 2 支持通过学校官方登录连接校园卡，读取登记宿舍并匹配电表。热水配置可核对本人身份和宿舍水控，正常首次设置无需抓包或导入个人配置。

Android 测试包为 0.2.0-alpha22；iPhone 测试包为 0.8.0 build 36，包含校园双余额小组件。

📦 [选择设备下载](https://jasonbeam.github.io/campus-daily/) · [下载及校验文件](https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0-beta.2)

📖 [安装与签名教程](https://github.com/JasonBeam/campus-daily/blob/main/docs/download.md) · 🔗 [连接与使用教程](https://github.com/JasonBeam/campus-daily/blob/main/docs/configuration.md)

✨ [界面预览](https://github.com/JasonBeam/campus-daily/blob/main/docs/previews/README.md) · [AI 使用教程](https://github.com/JasonBeam/campus-daily/blob/main/docs/ai-guide.md)

## 本版更新

- 学校登录后读取校园卡和登记宿舍；电表唯一匹配时自动保存，同名公寓需本人确认。
- 热水配置支持核对宿舍和水控编号，Android 可在热水页面进行只读连接检查。
- 校园账号、宿舍或设备变更时保护原有记录，避免旧查询结果覆盖新的选择。
- 使用本人 U 净账号管理常用洗衣机，查询状态、程序和价格。

## 注意事项

- 这是测试版。Android APK 可按手机提示安装；iPhone IPA 未签名，需要用自己的 Apple 账号签名。Safari 下载 IPA 后不会直接完成安装；免费个人签名通常约 7 天需要续签。
- Android alpha22 已在一台用户设备上确认安装和配置后可用。其他 Android 机型、iPhone 全新用户流程、第三方签名小组件，以及完整热水授权、出水和结算尚未完成验收。
- iPhone build 36 曾在用户设备上覆盖安装并保留余额、宿舍与结算记录；本次发布的重新构建 IPA 未再次实机安装。热水操作可能产生费用，请本人现场核对设备和官方结果。
- 本轮 iOS 核心测试 151 项、Android 单元测试 65 项通过；Android lint 有 43 条提示、无错误。构建与测试结果不能代替真实设备和交易验收。
- 安装包包含可被提取的通用热水平台参数，不含作者的个人账号、宿舍、水控编号、交易记录或 Apple 签名证书。请勿公开自己的密码、验证码、校园令牌、宿舍信息、设备二维码或交易链接。
- 界面预览使用示例数据，展示的是较早 Android 版本，页面细节可能与当前版本不同。

详细情况见[首次使用审查](https://github.com/JasonBeam/campus-daily/blob/main/docs/first-use-review-2026-10-29.md)和[配置教程](https://github.com/JasonBeam/campus-daily/blob/main/docs/configuration.md)。
