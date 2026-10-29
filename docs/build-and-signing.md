# 构建与签名

需要 macOS、完整 Xcode、Swift 6 工具链及 iOS 17+ 目标设备。开发记录使用 Xcode 27.1；不保证其他 Xcode 版本无调整可用。本文不要求修改全局 `xcode-select`。

## 支付宝 SDK

App 引用了 AlipaySDK-iOS 15.8.30。仓库保留 `Vendor/AlipaySDK-15.8.30/source.json` 和该包的 MIT LICENSE，不在源码首发准备稿里重新分发 SDK 二进制。

从支付宝官方开放平台或 CocoaPods 的 AlipaySDK-iOS 15.8.30 podspec 核对下载来源。开发时记录的归档 SHA-256：

```text
9391ce3555c86321d19a67eaf6b8a04702582476a90e19e3b75e141a33d98e70
```

`source.json` 提供对应来源 URL。下载后用 `shasum -a 256` 校验；不一致时停止并核对官方来源，不跳过检查。解压后将 `AlipaySDK.xcframework` 与 `AlipaySDK.bundle` 放入 `Vendor/AlipaySDK-15.8.30/`，保留其许可证。本次公开副本已通过脚本从记录的官方地址全新下载并校验哈希，再完成 iPhoneOS 不签名构建。

推荐先运行下载脚本，脚本仅下载和校验归档，不执行下载的代码；已有 SDK 目录时会停止，避免覆盖：

```sh
python3 tools/fetch_alipay_sdk.py
```

## 生成项目

```sh
python3 tools/generate_project.py
open CampusHotWater.xcodeproj
```

项目生成器不包含作者的开发团队、设备信息或配置。保留原图标，不运行历史开发目录的图标生成工具。

在本机准备仅含 `secret`、`sid`、`bleName`、`typeID`、`version` 的平台配置；禁止加入个人账号、宿舍或控制器。文件放在 Git 忽略的 `private/` 下。新直连构建会明确验证并复制这些共用参数进安装包，它们可能被提取；不要把真实文件提交到源码。

不签名 Release 构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CampusHotWater.xcodeproj -scheme CampusHotWater \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
  CAMPUS_WATER_PROFILE_PATH="$PWD/private/distribution/WaterPlatformProfile.json" build
```

## 自行签名

1. 在 Xcode 登录自己的 Apple 账号。
2. 选择自己的 Team 与可用的 Bundle Identifier。
3. 若更改 Bundle Identifier，同时核对 `App/Info.plist` 的 URL scheme 与 `App/AlipayBridge.swift` 的 `scheme`，使支付宝回跳一致且唯一。
4. 选择自己的 iPhone 运行，按系统提示在手机完成开发者模式、信任与权限操作。
5. 首次使用时在 App 内打开学校官方登录页，核对校园卡与宿舍信息。Beta 2 安装包包含通用平台配置，由本人学校登录核验身份；安装包不含个人身份。Beta 1 及更早版本没有本版的自动接入流程。

免费 Personal Team 通常约 7 天后需重新签名。没有现成 TestFlight；不提供作者的个人开发签名包、描述文件或设备列表。不同签名身份或 Bundle Identifier 可能改变沙箱和钥匙串访问范围，已有未决交易时不要随意换身份、卸载或覆盖安装。

## 离线测试

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native --scratch-path /tmp/campus-daily-tests
```

Swift 核心测试不需要个人配置，不联网发起交易，也不操作蓝牙。本轮 Beta 2 的核心测试为 110 项 XCTest 与 41 项 Swift Testing，共 151 项通过；iPhoneOS Release 构建和静态分析另行核对。离线测试和构建成功不代表真实出水、结算或付款已经验收。

## 小组件与重新签名

签名时必须保留 `PlugIns/CampusDailyWidget.appex`，并为主 App 和小组件授予相同的默认钥匙串分组。若修改 Bundle Identifier，请同步修改扩展标识及两份 entitlements；不能只签主 App 或移除扩展。不同第三方重签工具对扩展和权限的支持不同，不能保证所有工具都保留小组件能力。

可在本机对已签名 App 做静态检查：

```sh
python3 tools/check_widget_signature.py --app /absolute/path/CampusHotWater.app
```

静态检查通过后，仍需在本人手机打开 App 同步余额，再添加「校园双余额」小组件核对。更新节奏由 iOS 安排，并非持续实时刷新。

早期 build 31 曾在同一签名团队的真实 iPhone 验证主 App 和原生小组件读取同一份校园卡、电量及电费数据。Beta 2 build 36 的已签名覆盖安装保留了余额、宿舍和既有记录；公开无签名 IPA 未重新安装验收。更换团队后的第三方重新签名仍需单独验收，不保证会保留扩展或正确权限。

## 打包无签名 IPA

```sh
python3 tools/package_public_ipa.py \
  --app build/Build/Products/Release-iphoneos/CampusHotWater.app \
  --platform-profile "$PWD/private/distribution/WaterPlatformProfile.json" \
  --output artifacts/local-candidate
```

脚本要求包内通用配置与本次显式指定的文件一致，同时保留小组件、拒绝个人配置和开发签名。不要打包已安装手机的 App 或 Debug 私人沙箱。构建不会自动发布或部署云服务。
