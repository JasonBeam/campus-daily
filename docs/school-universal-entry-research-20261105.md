# 学校平台多人通用入口复核（2026-11-05）

本轮只读研究，未改 App、未安装、未注册或支付认证费用，未操作任何充值或设备。以下是官方能力核查，不是真机验收结果。

## 已确认的更合适路线：OpenSDK

本轮重新成功读取微信官方现行文档及 Android、iOS、HarmonyOS 三端示例（之前失败的读取本轮通过正确处理HTTP压缩成功）。官方文档明确：

> 移动应用拉起小程序功能已向全体开发者开放，开发者在微信开放平台账号下申请移动应用并通过审核后，即可获得移动应用拉起小程序功能权限。
> 对于已通过认证的开放平台账号，其移动应用可以跳转至任何合法的小程序，且不限制跳转的小程序数量。
> 若移动应用未上架，则最多只能跳转小程序100次/天，用于满足调试需求。

因此，对于已认证账号的合规移动应用，并不要求取得学校的小程序AppSecret，也不能笼统声称一定要把学校小程序关联到本人的账号。此结论不扩展到未认证账号或未审核应用。

两端OpenSDK示例均使用学校小程序原始ID作为目标，path为空可打开首页。既有真机资料已核对学校目标原始ID gh_0f7fc7e32f8e。此ID是公开目标标识，不是校日常自身的微信移动应用AppID；后者必须单独申请审核，不能冒用学校AppID。

校日常工程目前未接入微信OpenSDK、未配置自己的微信移动应用AppID及完整回调/Universal Link。Android还需登记与实际发行包一致的包名和应用签名；iOS需完成对应开放平台配置。二次签名、自签名包不能只因代码相同就声称兼容；需核对实际分发身份。未查询用户开放平台账号后台，不能据工程缺配置认定账号尚未注册。

SDK支持鸿蒙原生应用的官方示例，但校日常当前是Android工程，不因此声称已有HarmonyOS原生包。平台可用不代表所有手机、微信版本、账号以及签名均已经验收。

## 学校直接通用链接

本轮读取学校信息技术中心官网 https://xxzx.gdbtu.edu.cn/ ，其“e广工商大办事大厅”按钮仍指向使用指南，并非一个新发现的通用小程序URL Link。现行指南 https://xxzx.gdbtu.edu.cn/info/1341/1131.htm 提供官方使用说明和小程序入口介绍，没有取得已经可跨微信用户实测成功的新桌面外链。

学校官网“一网通办”使用 https://cas.gdbtu.edu.cn/cas/login 。本轮匿名只读请求返回HTTP200、标题“登录 - 统一身份认证”。这是公共网页登录入口，用户各自登录；不能当作已打通微信小程序或充值支付的证明。

现行微信明文Scheme文档仍要求小程序管理后台声明此能力，并使用已发布的真实页面。学校pages/applet/index这一路径此前已真机测试失败，不能仅换参数再宣称可用。学校维护方若开放明文Scheme或正式签发用于多人分发的URL Link，可以再测试；我们不能自行用学校凭据生成链接。

此前桌面链接的“其他用户已访问”截图不能单独证明锁定手机硬件或具体微信账号，只能证明该链接不适合当前共享方式。普通URL Link支持多人访问的能力，不等于该桌面产品链接适合多人分发。

## 建议

1. 若具备已认证的微信开放平台账号，为校日常申请/核对通过审核的移动应用，接OpenSDK打开学校首页；这是App内一键直达的优先方案。
2. 若暂不具备条件，请校方提供明确可多人分发的链接或开放明文Scheme；在获得以前保留学校官方小程序码与搜索/收藏入口。
3. 正式验收至少覆盖两个不同微信身份、iOS及Android的实际发行签名，分别核对“打开微信/正确学校首页/本人登录”三步，不以sendReq/open的返回值代替UI验收。不为验证创建充值订单。

官方资料：
- https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Launching_a_Mini_Program/Launching_a_Mini_Program.html
- https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Launching_a_Mini_Program/Android_Development_example.html
- https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Launching_a_Mini_Program/iOS_Development_example.html
- https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Launching_a_Mini_Program/OHOS_Development_example.html
- https://developers.weixin.qq.com/miniprogram/dev/framework/open-ability/url-scheme.html

官方HTML副本保存于本机/tmp/wechat-*-20261105.html；未公开推送。
