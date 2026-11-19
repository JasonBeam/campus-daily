# 校日常 | Campus Daily

校日常是面向广东工商职业技术大学的非官方校园生活 App，支持 iPhone 和 Android。校园卡余额、宿舍电费、热水和 U 净洗衣放在一起，日常使用时少切换几个入口。

登录学校官方账号后，可以查看校园卡和学校登记的宿舍信息，匹配宿舍电表、核对热水水控。iPhone 还可以通过桌面小组件查看校园卡余额与宿舍电费。

📦 [选择设备下载](https://jasonbeam.github.io/campus-daily/) · 📱 [iPhone：TestFlight 公开测试](https://testflight.apple.com/join/cgy67KMX) · 🤖 [Android：最新安装包](https://github.com/JasonBeam/campus-daily/releases/latest)

📖 [安装与使用](#安装与使用) · [版本记录](CHANGELOG.md) · [隐私说明](docs/privacy.md) · [开发者看这里](#开发者)

## 功能介绍

以下介绍 iPhone 0.10.0 的功能，通过 TestFlight 安装和更新；Android 以当前安装版本为准，充值等部分功能和 iPhone 不同。

- 校园卡：登录学校账号后查看余额、消费记录和登记宿舍。
- 宿舍电费：按校区、公寓、楼栋、楼层、房间一层层匹配电表；有同名公寓时，按提示选是哪一间。
- 宿舍热水：在水控旁边连上蓝牙，一个按钮完成「开始洗澡」→「结束并结算」→「开始下一次洗澡」。已保留为待核对的洗澡记录不会再提交结算，可去校园卡消费记录核对；扣费记录可能约 1 小时后才出现。
- U 净洗衣：保存常用洗衣机，扫码下单，用支付宝付款；可选正常洗衣或立刻洗衣（试用）。已结束订单在「最近」显示从下单时间算起 7 天内的，最多 30 笔；本机保留和清理规则见隐私说明。
- 洗衣提醒：按本机跟踪的订单倒计时提醒，可在设置里开关。
- 校园充值：校园卡和电费在同一个入口，点了先复制学校微信服务的名字再打开微信，充值和到账由学校处理。
- 两套主题：暖橙和清爽，可以在设置里切换；洗澡或洗衣订单进行时暂不能换。两套逻辑相同，页面不同。
- 先看看示例：不登录，用示例数据先看看整个 App 长什么样。
- 反馈问题：在设置里写下遇到的问题，可以附截图。之后打开 App 时，如果 iOS 提供了可用的崩溃记录，App 会试着发送崩溃报告。发了什么见[隐私说明](docs/privacy.md)。
- 小组件和灵动岛：桌面查看校园卡余额与宿舍电费；洗澡时锁屏和灵动岛显示进度。Siri 和快捷指令可以开始洗澡、结束并结算。

Android 有版本检查和更新提醒；iPhone 版由 TestFlight 更新。

## 安装与使用

- **iPhone**：先在 App Store 装好 TestFlight，再打开 [TestFlight 公开测试链接](https://testflight.apple.com/join/cgy67KMX) 安装。支持 iOS 17 及以上。从 GitHub 自签名旧版换过来的，是另一个 App，第一次打开要重新登录学校账号、再设置一次宿舍。
- **Android**：从 [最新 Release](https://github.com/JasonBeam/campus-daily/releases/latest) 下载 APK，按系统提示允许安装。支持 Android 6.0 及以上。鸿蒙 6.0 至 7.0 可以用卓易通安装，但可能跳不到支付宝。

第一次使用：App 会依次带你登录学校账号、确认宿舍，再站在水控旁边核对一次水控（只读，不会开水，也可以以后在设置里核对）。电表按校园目录自动匹配。洗衣用本人的 U 净账号登录，再扫描洗衣机二维码。

## 注意事项

- 校日常由个人开发，不代表学校或相关服务平台，当前围绕广东工商职业技术大学环境制作。
- 两个平台都还是测试版。iPhone 这轮新增或重写的热水关水、结算与异常核对，立刻洗衣的整笔实付流程（包括留在支付宝时启动、返回后订单跟进和提醒时机），以及换账号后的热水设置、小组件刷新、校园卡扣费匹配、折叠屏显示，还没有完整的真机验收。Android 新增功能也还没真机验收。热水操作会产生费用，请在现场核对设备，费用以校园卡记录为准。
- 请使用本人账号，不要公开密码、验证码、校园令牌、学号、宿舍信息、设备二维码或交易链接。
- 安装包里带着热水平台给所有人共用的同一组平台参数，任何人都能从安装包里取出来。这是平台的鉴权风险，客户端无法单方面修好。安装包不含作者的个人账号、宿舍、设备或交易记录。存了什么、发给了谁，见[隐私说明](docs/privacy.md)。

## 开发者

### 从源码运行（iPhone）

需要 macOS、Xcode 26（Swift 6）、[mise](https://mise.jdx.dev) 和 node（`mise install` 按 `mise.toml` 装好）。

```sh
mise setup        # 拉取支付宝 SDK 和热水平台参数，放在 Git 忽略的目录
open XiaoRiChang.xcworkspace
mise test         # Core 包测试，不联网、不碰蓝牙
mise build        # 模拟器构建 App 和小组件
mise run check-public  # 提交前跑：构建、测试、隐私扫描
```

用自己的团队签名：新建 `Configuration/Developer.xcconfig`（不提交），写入 `DEVELOPMENT_TEAM = …`，需要时再写 `APP_BUNDLE_IDENTIFIER = …`。缺少热水平台参数时 Debug 构建只给警告，热水连不上。其他命令用 `mise tasks` 查看。

### 仓库结构

| 目录 | 内容 |
|---|---|
| `App/` | iPhone App 的界面和服务 |
| `Shared/`、`Widget/` | 小组件、灵动岛和主题 |
| `Packages/Core/` | 不含界面的逻辑和全部逻辑测试 |
| `platforms/android/` | Android 工程（`mise android`） |
| `Configuration/`、`Scripts/` | 版本号、包名、签名设置，以及构建、打包和隐私检查脚本 |

架构和外部接口见 [docs/architecture.md](docs/architecture.md)，仓库规则见 [AGENTS.md](AGENTS.md)。

源码采用 [MIT License](LICENSE)，第三方组件保留各自许可证。
