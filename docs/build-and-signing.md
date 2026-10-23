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

不签名构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CampusHotWater.xcodeproj -scheme CampusHotWater \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

## 自行签名

1. 在 Xcode 登录自己的 Apple 账号。
2. 选择自己的 Team 与可用的 Bundle Identifier。
3. 若更改 Bundle Identifier，同时核对 `App/Info.plist` 的 URL scheme 与 `App/AlipayBridge.swift` 的 `scheme`，使支付宝回跳一致且唯一。
4. 选择自己的 iPhone 运行，按系统提示在手机完成开发者模式、信任与权限操作。
5. 在 App 设置里导入本人配置。安装成功不等于登录、用水或付款成功。

免费 Personal Team 通常约 7 天后需重新签名。没有现成 TestFlight；不提供作者的个人开发签名包、描述文件或设备列表。不同签名身份或 Bundle Identifier 可能改变沙箱和钥匙串访问范围，已有未决交易时不要随意换身份、卸载或覆盖安装。

## 离线测试

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native --scratch-path /tmp/xiaorichang-tests
```

测试不需要个人配置，不联网发起交易，也不操作蓝牙。0.7.0 build 22 已运行通过 54 项 XCTest 与 37 项 Swift Testing，共 91 项。
