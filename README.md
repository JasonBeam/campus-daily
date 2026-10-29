# 校日常 | Campus Daily

面向广东工商职业技术大学的非官方校园生活 App，把校园卡余额、宿舍电费、热水和 U 净洗衣集中到 iPhone 与 Android，少在不同服务入口之间来回切换。

登录学校官方账号后，App 可读取校园卡和学校登记的宿舍信息，并匹配宿舍电表；热水连接会核对附近水控设备编号。iPhone 还可在桌面小组件查看校园卡与电费。

📦 [选择设备并下载 Beta 2](https://jasonbeam.github.io/campus-daily/) · [GitHub Release](https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0-beta.2)

📖 [安装、签名与续签说明](docs/download.md) · 🔗 [连接与配置说明](docs/configuration.md)

✨ [界面预览](docs/previews/README.md) · [AI 使用教程](docs/ai-guide.md) · [Beta 2 版本说明](docs/release-0.8.0-beta.2.md)

## 功能概览

- 学校官方网页登录后查看校园卡余额和学校登记的宿舍信息。
- 根据宿舍目录自动匹配电表；遇到同名公寓时，由本人确认一次位置。
- 识别附近水控编号，再按 App 页面提示使用热水。
- 登录 U 净账号后保存常用洗衣机，查询状态、程序和价格。
- iPhone 桌面小组件显示校园卡与宿舍电费。

## 安装前

- Android 测试版是 APK，下载后按手机提示安装；目标系统为 Android 6.0 或更新版本。
- iPhone 测试版是无签名 IPA，需要使用自己的 Apple 账号签名后安装；目标系统为 iOS 17 或更新版本。Safari 下载 IPA 不会直接完成安装。
- 首次使用请登录本人的学校账号和 U 净账号。不要把密码、验证码、校园令牌、学号、宿舍或设备二维码发给开发者或 AI。

Beta 2 仍是测试版。发布前没有完成所有机型上的新用户配置、第三方签名小组件和完整热水授权、出水与结算验收；真实操作可能连接设备并产生费用，请本人现场核对设备和官方结果。

本项目由个人开发，不代表学校、校园服务平台、U 净或支付宝，也不保证其他学校可用。公开安装包含通用热水平台参数，安装包持有者可能提取；不会包含作者的校园账号、宿舍、水控设备或交易记录。细节见[配置与隐私说明](docs/configuration.md)。

源码采用 [MIT License](LICENSE)，第三方组件保留各自许可证。
