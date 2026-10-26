# 下载校日常

从 [GitHub Releases](https://github.com/JasonBeam/campus-daily/releases/tag/v0.7.0) 下载，当前公开包：

- [0.7.0 build 28 无签名 IPA](https://github.com/JasonBeam/campus-daily/releases/download/v0.7.0/CampusDaily-0.7.0-build28-unsigned.ipa)
- [IPA 的 SHA-256 校验文件](https://github.com/JasonBeam/campus-daily/releases/download/v0.7.0/CampusDaily-0.7.0-build28-unsigned.ipa.sha256)
- [与 build 28 对应的源码快照](https://github.com/JasonBeam/campus-daily/releases/download/v0.7.0/CampusDaily-0.7.0-build28-source.zip)

用 Safari 打开下载链接，可将 IPA 保存到「文件」。下载完成后需要自行签名安装；网页下载不会直接安装 App，也不提供证书、TestFlight 或在线签名服务。签名方法由使用者自行选择和研究，免费 Apple Personal Team 通常约 7 天需重签。

仅面向广东工商职业技术大学、iOS 17+ 的测试用户。安装后使用自己的学校和 U净账号，扫码绑定自己的洗衣机。

**首次热水配置仍有门槛**：公开 IPA 不包含作者的个人配置或共享平台签名参数。首次读取宿舍/水控仍需合法取得的本机平台配置；只下载和签名，不能保证热水功能开箱即用。不要向他人索要或在公开位置上传完整配置、token、HAR、手机号、学号或设备二维码。

已有未结算用水或待确认订单时，先在原 App 确认结果。更换签名身份、Bundle ID 或卸载可能影响数据与钥匙串访问。

相关资料：[配置](configuration.md) · [AI 辅助上手](ai-guide.md) · [构建说明](build-and-signing.md) · [排错](troubleshooting.md)。

## build 28

- 原生清爽布局，校园卡与宿舍电量展示，保留现有小组件方向。
- 修正充值登录状态误判，进入学校官方充值页面。
- 只读核对热水设备后展示名称、硬件编号、信号与核对时间；按宿舍硬件编号区分同名水控。
- 76 项 XCTest + 41 项 Swift Testing 通过；公开 Release 不签名构建通过。
- 实机验证充值入口与水控只读识别，未进行本轮充值或出水交易。公开包已检查不含开发签名、描述文件或私测配置；仍需使用者自行签名和配置。

源码快照与本次 IPA 对应；v0.7.0 标签自动生成的 Source code (zip/tar.gz) 仍为首发代码。如需自行构建 build 28，请下载上面的显式源码快照。
