# 校园卡、电费充值与微信接入审计 — 2026-11-02

## 结论

已在学校当前线上收银台脚本中找到“请在微信中支付”的直接来源。这不是校日常自己拼出的报错，也不是仅靠增加 weixin URL 跳转就能解决的问题。

学校收银台支持微信内网页的 JSAPI 支付，以及其自身小程序内的支付路径；本次查看的 wxPay 实现没有给普通外部 App WebView 提供 H5 或原生 APP 支付分支。对校日常当前版本，优先保留学校收款与入账，通过学校正式支持的微信入口办理。不能把系统 Safari/Chrome 当作已经验证可用的替代收银台。

本轮只读审计，没有获取支付参数、创建订单、签约或进行真实充值；没有新增商户号、SDK 或后端。

## 当前自有 App

| 端 | 位置 | 现有行为 |
| --- | --- | --- |
| iOS | App/CampusRechargeView.swift | 通过独立 WKWebView 打开学校页面，注入经学校验证的登录上下文；仅对用户点击产生的部分支付 scheme 做系统打开 |
| 共享核心 | Sources/WaterCore/CampusWebSession.swift | 校园卡打开 /ykt-view/recharge?isbind=1；电费先到 /ykt-mini/api/electricnew/getPowerUrl，携带学校返回的账户标识 |
| Android | ui/OfficialBrowser.kt | WebView 启用官方页面需要的 JS/DOM storage，交接学校上下文；仅在手势导航时转交 alipays/alipay/weixin |

两端没有实现微信 JSAPI 容器的 WeixinJSBridge。普通 WebView 也不会因为修改 User-Agent 就获得这个桥。支付宝洗衣 SDK 是另一笔业务的实现，不能拿来证明校园充值微信支付已打通。

App 内的 localStorage 登录上下文不会自动进入微信浏览器或其他系统浏览器。直接把当前地址复制到另一个 App，不代表用户仍保持学校登录；不应把登录 token、账户上下文拼到跳转链接里尝试交接。

## 学校线上页面的直接证据

本轮重新读取学校公开静态资源，未调用业务下单接口：

- https://ecykt.gdbtu.edu.cn/ykt-view/
- https://ecykt.gdbtu.edu.cn/ykt-view/js/app.c35ac1d0.js
- https://ecykt.gdbtu.edu.cn/ykt-view/js/RechargeConfirm.23bf4e44.js
- https://ecykt.gdbtu.edu.cn/ykt-view/js/Cashier.1107cdef.js
- https://ecykt.gdbtu.edu.cn/ykt-view/js/PowerNewIndex.1e796933.js
- https://ecykt.gdbtu.edu.cn/ykt-view/js/BusPowerNew.98bcacb9.js

### 报错条件

Cashier 的 checkIsWx 检查 MicroMessenger，并通过微信 JS SDK 的 miniProgram.getEnv 区分：

| isWx | 环境 | wxPay 行为 |
| --- | --- | --- |
| 0 | 非微信环境 | 弹出“请在微信中支付” |
| 1 | 微信内网页 | 调学校 /api/pay/wxJsPay，之后通过 WeixinJSBridge 调起支付 |
| 2 | 学校小程序环境 | 用 miniProgram.redirectTo 进入学校小程序原生付款页 |

小程序页路由包括 /pages/pay_mini/pay_mini 和渠道相关的 /pages/pagesCustom/pay/pay。这些是学校容器内部路由，不是已经验证可从校日常外部使用的支付链接。

因此，在普通 WKWebView/Android WebView 收到这个提示，是收银台环境检查的预期结果。只改 scheme 拦截无法让 isWx=0 的路径生成支付跳转；伪装 MicroMessenger 也不能提供实际微信桥或有效的微信身份。

### 两项业务分别下单，共用收银台

校园卡 RechargeConfirm 源码显示先走学校 balRechargeApply、balRechargeOrder，然后进入 /cashier。电费 PowerNewIndex 和 BusPowerNew 同样先走学校电费自己的建单流程，再带 amount/orderid 进入 /cashier。

这些接口本次仅作为脚本中的字符串和调用关系查看，没有请求。发现前端内部接口不等于学校已授权第三方对接，也不等于已验证实际扣款或入账。

收银台还会按学校订单查询 getOrderSupportPayType，说明支付方式由具体学校订单决定；页面内出现多种通道代码，不能据此宣布本人的校园卡或电费支持全部通道。

## 对所提供研究建议的核对

方案 A → B → C 的优先级适合当前项目，但 A 需要进一步限定：

1. 当前学校的微信支付分支要求微信环境，不能把“官方 HTTPS 网页”直接等同于“系统浏览器可以付”。
2. 官方微信文档已核对到“不得由外部 App 或网页跳转小程序收银台完成交易”的说明。OpenSDK 可以导航到小程序，不代表允许通过该导航承载这笔支付。
3. 自行申请微信商户号不能替学校的一卡通或电表入账。原生 APP 支付只有在收款主体、AppID、商户绑定及学校业务接口都明确后才值得继续研究。

本轮直接读取的微信官方资料：

- https://pay.wechatpay.cn/doc/v3/merchant/4054257696
- https://pay.wechatpay.cn/doc/v3/merchant/4015478291

没有独立确认用户提供文章中的“2026-10-30 更新”具体日期，本结论依据本轮读取到的规则正文。

## 建议的下一步

优先把两端充值入口说明清楚：学校微信支付目前需要进入学校正式微信服务；保留学校官方收款、用户确认目标和金额、以及充值后主动刷新余额。不要把无法工作的内嵌支付按钮呈现成已接通。

接下来只需核实学校公众号/小程序的正式入口与重新登录流程，判断学校是否提供适用于外部 App 的授权链接或支付产品。没有学校提供的可用链路时，只做明确的官方入口引导，不继续尝试伪装微信环境。

若校方愿意开放接口，再单独设计校园卡和电表订单模型，区分待支付、支付已确认、入账处理中、已入账和失败；到账以学校流水/业务状态为准，单次余额变化也不能独立归因于本笔充值。

本轮没有改动充值功能源码或诊断包，不需要重新构建；真实充值与到账仍未验收。

## 复核指纹

本轮静态副本保存在 /tmp/campus-recharge-audit-20261102，不含个人登录态：

| 文件 | SHA-256 |
| --- | --- |
| app.js | 1043ee8aa9de8c0d61d7c9f987cf9e71e8468e2eeb4cf8778cb09026c7720069 |
| RechargeConfirm.js | b7ab2871c1e32a02538690b69544c600e25b128c6d65aaac30f5b2b23eb16ccc |
| Cashier.js | c4def4aa5002a77a26abbf3da8d7bcdf8b96251af5205f42c846ad05d7132725 |
| BusPowerNew.js | 678a0f3f340bef91508d77dacc70893940f9163836fa89603e88dcebc4d928c4 |
