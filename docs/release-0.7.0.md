# Campus Daily / 校日常 0.7.0

![校日常 0.7.0 宣传封面](https://raw.githubusercontent.com/JasonBeam/campus-daily/main/docs/social/xhs-01-cover.png)

校日常是面向广东工商职业技术大学的非官方 iPhone 工具。

我做它的原因很直接：每天都要用的校园卡、宿舍热水和 U净洗衣分散在不同入口里，小程序跳转和无关页面太多。这个版本把常用数据与操作集中起来，也让宿舍热水和洗衣机可以少走几次重复步骤。

## 这个版本有什么

- 首页查看校园卡余额、宿舍、热水结算记录和常用洗衣机。
- 在学校官方网页内登录，并选择校区、楼栋、楼层和寝室绑定热水。
- iPhone 直接通过蓝牙连接水控，提供「开始洗澡」「结束结算」快捷指令动作。
- 使用本人 U净手机号与验证码登录，扫码或从照片识别洗衣机二维码。
- 保存多台常用洗衣机，查看空闲状态、程序和实时价格。
- 核对订单后跳转支付宝；支持取消符合条件的未付款预约。
- 交易结果未知时保留本机状态，避免自动重复授权、付款或结算。

## 界面流程演示

仓库内有三组 GIF 和 MP4：热水、洗衣、首次配置。它们是脱敏界面流程模拟，不代表真实出水、扣费或机器启动录像。

## 下载与安装

Release 资产包含：

- `CampusDaily-0.7.0-build22-unsigned.ipa`：无签名开发包，下载后必须用自己的 Apple 身份签名才能安装。
- `CampusDaily-0.7.0-build22-unsigned.ipa.sha256`：下载完整性校验。
- GitHub 自动提供的源码 zip/tar 压缩包。

这个 IPA 不包含作者的开发签名、设备 UDID、描述文件或共享平台签名参数。使用自己的 Mac/Xcode 或可信的 SideStore/AltStore 流程重签后，才能装到自己的设备。

## 配置教程与 AI 上手

优先使用 App 内流程：

1. 学校官方网页登录。
2. 选择校区、楼栋、楼层和寝室。
3. U净手机号 + 验证码登录。
4. 扫描洗衣机机身二维码并保存常用机器。

完整教程：

- [配置与使用边界](https://github.com/JasonBeam/campus-daily/blob/main/docs/configuration.md)
- [构建与签名](https://github.com/JasonBeam/campus-daily/blob/main/docs/build-and-signing.md)
- [AI 辅助上手](https://github.com/JasonBeam/campus-daily/blob/main/docs/ai-guide.md)
- [故障排查](https://github.com/JasonBeam/campus-daily/blob/main/docs/troubleshooting.md)

## 当前门槛

- 目前没有 TestFlight；公开 IPA 是无签名开发包，必须自行签名。
- 免费 Apple Personal Team 通常每 7 天要重新签名。
- 需要 macOS、完整 Xcode、可签名 Apple 账号和本人合法取得的学校/U净登录条件。
- 当前重点验证的是我实际使用的一种水控和本校流程，不代表其他学校或所有设备通用。
- 首次热水宿舍读取仍依赖共享平台签名参数。源码不包含该参数；Debug 私测包不能公开分发。稳定公开前还需要服务端签名代理或移除这项客户端依赖。

## 验证记录

- 0.7.0 build 22：
  - 54 项 XCTest + 37 项 Swift Testing，共 91 项离线测试通过。
  - Debug iPhoneOS 签名构建、Release 不签名构建、Xcode 静态分析均通过。
  - 本地设备包严格代码签名校验通过，未上传 GitHub。
- 本人 0.7.0 实机已完成校园登录、宿舍保存、U净短信登录、常用机器查询和重启持久化检查。
- 未把构建、单元测试或支付跳转等同于真实扣费、水流出水和洗衣机启动。

## 自行构建

```sh
python3 tools/fetch_alipay_sdk.py
python3 tools/generate_project.py
open CampusHotWater.xcodeproj
```

在 Xcode 中用你自己的 Team 和 Bundle Identifier 签名。不要使用作者的设备、描述文件或本机配置。

遇到问题请先读 [配置与使用边界](https://github.com/JasonBeam/campus-daily/blob/main/docs/configuration.md)、[构建与签名](https://github.com/JasonBeam/campus-daily/blob/main/docs/build-and-signing.md)、[AI 辅助上手](https://github.com/JasonBeam/campus-daily/blob/main/docs/ai-guide.md)和[故障排查](https://github.com/JasonBeam/campus-daily/blob/main/docs/troubleshooting.md)。

不要在 Issue 中上传配置、HAR、Cookie、token、手机号、学号、精确宿舍、设备二维码、付款链接或签名文件。
