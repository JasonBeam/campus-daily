# 校日常 | Campus Daily

校日常是面向广东工商职业技术大学的非官方校园生活 App，支持 iPhone 和 Android。校园卡余额、宿舍电费、热水和 U 净洗衣放在一起，日常使用时少切换几个入口。

登录学校官方账号后，可以查看校园卡和学校登记的宿舍信息，匹配宿舍电表、核对热水水控。iPhone 还可以通过桌面小组件查看校园卡余额与宿舍电费。

📦 [选择设备下载](https://jasonbeam.github.io/campus-daily/) · [查看 0.8.0 版本](https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0) · [版本记录](CHANGELOG.md)

## 功能介绍

- 校园卡：登录学校账号后查看余额和登记宿舍。
- 宿舍电费：根据宿舍目录匹配电表；有同名公寓时，按提示确认位置。
- 宿舍热水：核对宿舍和水控设备编号，按页面提示使用。
- U 净洗衣：登录本人账号，保存常用洗衣机，查看状态、程序和价格。
- iPhone 小组件：在桌面查看校园卡余额与宿舍电费。

## 安装

- **Android**：下载 APK 后按系统提示允许安装。支持 Android 6.0 及以上。
- **iPhone**：IPA 是无签名包，需要用你自己的 Apple 账号签名后才能安装（Safari 下载不会直接安装）。支持 iOS 17 及以上。免费 Personal Team 签名通常约 7 天后要重新签名。重新签名时要保留 `PlugIns/` 里的小组件，并让 App 和小组件用同一个钥匙串分组（小组件自己刷新还要同一个 App Group，没有的话由 App 刷新）。

第一次使用：App 会依次带你登录学校账号、选择是否用学校洗衣机、确认宿舍，再站在水控旁边核对一次水控（只读编号，不会开水，也可以以后在设置里核对）。电表按校园目录自动匹配；同名宿舍会按校区、公寓等位置区分。洗衣用本人的 U 净账号登录，再扫描洗衣机二维码。

## 注意事项

- 校日常由个人开发，不代表学校或相关服务平台，当前围绕广东工商职业技术大学环境制作。
- Android 安装包为 alpha23 测试包。
- Android 已由用户实机测试；鸿蒙 6.0 至 7.0 可通过卓易通安装使用，但用户反馈鸿蒙设备无法跳转支付宝。其他机型、iPhone 全新用户流程、第三方签名小组件，以及完整热水授权、出水和结算仍待验收。热水操作可能产生费用，请在现场核对设备和官方结果。
- 请使用本人账号，不要公开密码、验证码、校园令牌、学号、宿舍信息、设备二维码或交易链接。安装包含可被提取的通用热水平台参数，不含作者的个人账号、宿舍、设备或交易记录。存了什么、发给了谁，见[隐私说明](docs/privacy.md)。

## 从源码运行（iPhone）

需要 macOS、Xcode（Swift 6）和 [mise](https://mise.jdx.dev)。

```sh
mise setup        # 拉取支付宝 SDK（校验哈希）和通用热水平台参数，都放在 Git 忽略的目录
open XiaoRiChang.xcworkspace
mise test         # Core 包测试和脚本测试，不联网、不碰蓝牙
mise build        # 模拟器构建 App 和小组件，Debug 和 Release
mise run check    # 提交前的全部检查：构建、测试、隐私扫描
```

用自己的团队签名：新建 `Configuration/Developer.xcconfig`（不提交），写入 `DEVELOPMENT_TEAM = …`，需要时再写 `APP_BUNDLE_IDENTIFIER = …`。改了包名时，支付宝回跳 scheme 会跟着变。Debug 构建缺少热水平台参数时只给警告，热水连不上；直接用 Xcode 做 Release 构建缺少时会失败；`mise build` 的 Release 检查构建会放一份合成的平台参数，只用来编译，打包（`package-ipa`）仍然要真的那份。

其他命令用 `mise tasks` 查看：`scan`（提交前的隐私扫描，值清单 `LEAKCHECK_FILE` 和标记清单 `MARKER_PATTERNS` 都放在仓库外）、`check-widget-signature`、`package-ipa`、`android`。

## 仓库结构

| 目录 | 内容 |
|---|---|
| `App/` | iPhone App：`Application`、`Interface/<功能>`、`Services`、`Resources` |
| `Shared/` | App 和小组件共用的界面：小组件、灵动岛、主题 |
| `Widget/` | 小组件和灵动岛扩展 |
| `Packages/Core/` | 不含界面的逻辑：学校、热水、洗衣、最新数据、网络、存储，以及全部逻辑测试和合成样本 |
| `Android/` | Android Gradle 工程（`bash Android/build-android.sh`） |
| `Configuration/` | xcconfig：显示名、包名、团队、版本号 |
| `Scripts/` | 构建、打包和隐私检查脚本，通过 `mise` 调用 |

模块、依赖方向、状态机和每个外部接口见 [docs/architecture.md](docs/architecture.md)；仓库规则见 [AGENTS.md](AGENTS.md)。

源码采用 [MIT License](LICENSE)，第三方组件保留各自许可证。
