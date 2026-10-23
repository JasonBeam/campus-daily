# U净集成可行性调查 — 2026-10-22

## 结论与边界

可以复用已有 iPhone App 的原生界面与钥匙串，新增常用洗衣机列表。首次读取用户自己的机器二维码后保存原文和个人命名，后续按保存的机器查询，不要求每次重新扫描同一标签。

这属于代码与协议层面的可行性结论。已取得用户常用机器二维码，并观察到官方 App 的设备忙提示；尚未取得可供本项目使用的 U净登录会话或 U净流量记录，未下单、付款或发送启动指令，也没有在当前 App 增加不能实际工作的洗衣入口。

用户表示微信小程序、支付宝小程序、独立 App 均可使用。优先研究原生常用设备入口，付款衔接以实际可用的官方渠道为准，不把一个入口假定为所有机型通用。

## 已查看的主要来源

| 来源 | 能支持的结论 | 限制 |
| --- | --- | --- |
| [SleepyCelery/UjingWasherWatcher](https://github.com/SleepyCelery/UjingWasherWatcher) | 二维码原文携带 uuid；scanWasherCode 可解析设备；已有 Web/iOS shortcuts 调用思路 | 老项目，不能据此证明接口仍兼容用户机器；缺少 deviceId 不应直接等同于机器忙 |
| [thomaswan564/midea-washer-launcher](https://github.com/thomaswan564/midea-washer-launcher) | 有设备识别、动态模式、订单与 BLE 通道源码；区分 Nordic/Cypress 模块，明确云端与纯蓝牙机型不同 | 作者的 Android 机型验证不是本用户 iPhone 验收；其 Cypress 路径也未声明实机验证 |
| [funcfang/U-Clean-Reserve](https://github.com/funcfang/U-Clean-Reserve) | 可保存二维码图片并查询机器状态，说明扫码不是每次必须由相机完成的动作 | 只作为参考，没有执行；其中 TLS verify=False 不能沿用 |
| [U净官方设备介绍](https://www.ujing.com.cn/5) | 存在内置物联网卡、通电联网的洗衣机 | 不能推断用户现场机器也是此机型 |

已下载 11 个公开源文件到被 Git 忽略的 private/ujing-research，记录来源 URL、Git blob ID 和 SHA-256；未安装或运行第三方代码。完整来源清单在该目录 sources.json。普通完整源码调查无需 REA 原生引擎；目前没有选定用户自己的 U净包进行逆向，也不声称已经执行 REA 分析。

## 从源码核对到的路径

- 云端 API 主机：`phoenix.ujing.online`。
- `POST /api/v1/devices/scanWasherCode` 接收 `qrCode` 原文，返回设备标识与可下单信息。
- `GET /api/v1/app/washer/devices/program/info` 使用设备标识返回程序信息。
- 第三方源码还列出了订单创建、订单详情、支付和不同蓝牙模块的上报/取指令路径；本调查没有调用这些接口。
- 典型二维码为 `http://app.littleswan.com/u_download.html?type=Ujing&uuid=...`。不把此 URL 直接当作已验证的 iPhone 指定设备跳转链接；它可以是下载/分发入口，具体跳转仍需实际核对。
- U净是独立账号体系，不能拿校园热水或校园卡的 token 使用。
- 有的机器需要本地 BLE 启动，有的走云端；iPhone CoreBluetooth 不提供 Android 式按 MAC 地址直接连接，原生移植还需核对该机型广播和 GATT 特征。
- 参考项目有自动 HTTP 重试、伪造机型字段等实现细节，不直接复制成生产策略。尤其创建订单、付款和启动不能自动重放不确定请求。

## 推荐在 App 中的交互

1. 首次通过二维码照片、相机或粘贴原文添加一台机器，起名为「本层 1 号机」等；机器原文只保存在个人设备内。
2. 使用自己的 U净身份查询该机器详情、状态和程序；明确区分空闲、使用中、离线、登录失效和未知。
3. 从常用机器直接选程序；真实价格以服务器当前结果为准。下单与付款路径单独明确，付款由用户核对完成。
4. 按真实机型提供云端或近场蓝牙启动，保留订单状态，处理不确定结果，不能复用热水 FFE0 协议。

## 下一项缺失证据

已取得并解码用户常用洗衣机的二维码照片。下一步需要在设备空闲时验证指定机器页面和只读详情；无需支付订单。首次身份获取若必须验证码，由用户在手机完成，不在聊天索要验证码。

## 用户机器二维码的新证据

用户提供了机身照片。Vision/CoreImage 首次解码未成功，经本地 ZXing 解码得到唯一 QR 原文：主机 `q.ujing.com.cn`、路径 `/ucqrc/index.html`，包含 18 位数字的 `cd` 参数。机器原文保存在 Git 忽略的 private 目录，未写入公开文档或源码。

实际读取官方入口页成功（HTTP 200）。该页根据容器环境向
`https://phoenix.ujing.online:4443/api/v1/config/getConfigUrlByQrCodeV2`
发送 `{env, qrCode}`，不是旧项目里的直接 uuid 下载页。

按官方页实现查询配置（三次只读请求，无登录、订单、付款或设备控制）：

- `alipay`：官方成功返回 `alipays://platformapi/startapp`，appId 为 `2021002174638299`，页面为 `pages/home/home`，嵌套 query 包含完整的 `qrCode` 原文。
- `wechat` / `other`：成功返回 U净下载页，不是已验证的微信指定设备入口。

这证明官方提供了携带机器二维码的支付宝入口，但不等于已观察到小程序自动解析设备。用户补充其日常操作是「先进入小程序，再扫描后显示设备信息」。后续须只做页面导航验证，确认小程序对该 qrCode 参数的实际处理，不能仅凭跳转参数宣称已实现免二次扫码。

当前还没有识别出本机的云端/BLE 模块类型，也没有自己的 U净账号会话。照片足以确定入口与保存二维码，尚不足以确认洗涤程序、价格、运行状态或完整启动流程。

## 三端校园余额缓存

共享带账户范围、金额、查询时间的缓存可以减少重复查询；只有较新的有效结果覆盖旧值。缓存 TTL 内复用，过期才查询，并提供显式刷新。手机 App、Scriptable、ESP32 的共享传输与合并尚未实现，不能把当前各端独立刷新说成已经减少请求。

## 2026-10-22 中午实机观察

用户完成 U净独立 App 的微信授权后，观察到官方 App「扫码异常」页面显示「此设备正在运行中，请使用其他设备」。用户确认机器确在使用；这仅证明当前页面的忙提示，未取得机器编号、剩余时间、程序、价格或 BLE 模块信息。

从 Safari 输入官方返回的支付宝跳转链接后，手机进入支付宝「U净生活」首页，未观察到自动打开指定设备详情。期间存在用户手动导航（前台切换及相册选择），不能把后续页面变化全归于自动跳转，也不能据此声称免扫码已实现。

用户要求等机器洗完再继续。暂停设备详情验证，未下单、付款或启动洗衣机；本轮不添加未验证的 App 入口。

## 空闲后程序页验收

2026-10-22 12:52，恢复连接时官方 U净独立 App 已在「扫码洗衣」程序页。树与截图一致，显示一台 6.5kg 波轮机，四项程序如下（当时页面价格，不能硬编码为未来报价）：

| 程序 | 时长 | 价格 |
| --- | --- | --- |
| 普通洗 | 35 分钟 | ¥1.90 |
| 小件洗 | 25 分钟 | ¥1.70 |
| 单脱水 | 10 分钟 | ¥1.00 |
| 大件洗 | 61 分钟 | ¥2.20 |

具体设备名称、地点及截图路径存于 private/ujing-research/device-ui-observation-private.json。本轮没有点击「立即下单」，没有付款或启动机器。连接恢复时页面已存在，因此不能证明是我们的链接直接打开，也未获得原生集成所需的 deviceId、moduleType 或个人 U净 API 会话。免扫码入口仍需独立验证，后续程序和价格必须从实时接口取得。

## HAR与独立实时查询验收

用户提供 2026-10-22 12:57:03 HAR，含24条请求。实际设备解析和程序查询均 HTTP 200 / code 0。程序响应是 Brotli 压缩的 base64 内容，解压后与官方页面四项价格一致。扫码结果为 status=0、createOrderEnabled=true、moduleType=7、needSyncBLE=false、MAC为空。moduleType=7不能当成第三方已验证的 Nordic 1/Cypress 5；needSyncBLE=false 只说明该响应的同步标志，不证明付款后一定不需要近场启动。

复用用户自己的请求登录凭据，在 Mac 对同一二维码做设备解析与程序查询，两项再次 HTTP 200 / code 0，证实无需每次用相机扫码也能查询这台机器。缺登录凭据的对照请求明确返回 HTTP 401 / JWT token is missing。没有调用订单创建、付款、设备启动、绑定等接口。原HAR、凭据和设备标识只存本机private目录。

0.3.0新增常用洗衣机查询页、钥匙串独立配置、60秒查询冷却及失败保留上次值。接口域名固定、拒绝重定向，不沿用抓包中的Cookie、定位或设备ID头。查询路径仅包含扫码解析与程序查询。洗衣下单/付款/启动尚未集成。

## 0.4.0 订单与付款代码接入（待真实订单验收）

公开源码枚举将moduleType=7定义为TYPE_4G。结合本机返回MAC为空及needSyncBLE=false，采用云端订单流程，不移植Nordic/Cypress指令。但付款后真实启动行为仍需本机订单验证。

接口位置及参数来自参考源码：POST orders/create，GET orders/{id}/detail，GET payment/methods，GET payment/arguments。payment/arguments可能返回skipPay并有财务副作用，不能用GET名义当作只读预检。此轮没有调用下单、付款参数、取消或启动接口。

接入支付宝官方SDK 15.8.30，来源CocoaPods trunk podspec指向的alipayobjects.com归档。Vendor内保留MIT许可证、源podspec、下载归档SHA256；未运行第三方项目。请求使用U净后台签发订单串，App中无商户私钥。不传chooseSign=1，不主动选择免密签约；仍在请求付款参数前由用户确认可能扣款及启动设备。SDK回调不作为最终付款证明，只触发服务器订单查询。

下单先原子保存creating标记，付款参数请求前保存paymentRequested标记。超时、崩溃或存储错误后不自动重复财务请求；配置更换在未决订单期间禁用。当前未提供未知结果的自动清除，也未实现取消/退款；需到U净官方订单核对。

## 0.4.1 实际预约失败恢复调查

用户在13:22点击本App的单脱水下单，随后反馈没反应。读回本地checkout记录：stage=creating、programId=50、无订单号。只读扫码解析返回属于本人的有效订单；官方App显示已预约、去支付、自动取消倒计时。只读订单详情证明机器、模式、金额与本地发起时间吻合。随后订单详情为status=53、payFlag=0，已取消且未支付。调查没有新建、取消或支付任何订单。原订单号及完整响应保存在private。

没有保存原始创建响应，因此不能断言是哪一个原始返回字段导致首次未完成。已确认的问题是原实现要求创建回执包含完整订单详情，且creating状态缺少按本人活动订单恢复的路径。改为最小回执解析、先持久化订单号再查详情；若回执丢失，仅使用本人的扫码结果候选，并核对设备、程序、时间、金额再恢复。不能仅凭机器号自动接管任意历史订单。

对已知旧单，开发引导文件只含该订单号，App启动时仍通过本人的接口读取并核对上述字段，再恢复本机记录；成功后删除引导文件。保留已取消历史，不清除未决记录来绕过防重。

只读payment/methods实际返回alipayF2F、branchType=0，没有alipay。付款通道选择改为按真实列表优先alipay/其次alipayF2F；付款参数调用仍须用户明确确认。增加对后端返回的确切https://qr.alipay.com地址的受限解析；没有构造二维码地址、没有猜测订单支付URL，也没有请求本订单的payment/arguments。F2F付款参数真实响应、支付宝唤起及付款后的机器启动尚未验收。

另外按官方旧下载页获取了其OSS公开APK，仅静态查看资源，无执行。该归档是较旧Cordova结构，没有alipayF2F文本，不能作为当前通道行为证据；当前2.4.18应用商店页也没有公开直链，因此没有借此声称已还原现版收银台。

## 0.4.2 取消预约与支付诊断

按已读参考源码接入POST /api/v1/orders/{id}/cancel，body含orderId。取消入口用于本人的未支付预约：点击后重新读取服务器详情，核对设备、程序、状态10/17及payFlag=0，再持久化cancellationRequested并单次提交；之后只读查询最终结果。已支付/运行/未知状态不发取消请求，取消结果未知不重复POST。付款尝试后仍未支付的预约也可通过此流程取消，当前订单已结束则只更新本地，不再发取消。没有新增自动退款或停机功能。

GitHub README与AlipayLauncher.kt已从raw.githubusercontent.com重新读取。作者使用channel=alipay、payInfo.orderInfo及Android PayTask.payV2，没有alipayF2F专用实现。GitHub API触发公开速率限制后改读公开raw文件，查询网页得到的通用当面付项目不能证明U净此账号的具体返回。

用户再次尝试的13:41预约后来status=53/payFlag=0；当前没有有效待付款单，也没有本次失败的原始payment/arguments返回。因此不能从已取消订单推断跳转失败唯一原因。新增手机本地受文件保护且排除备份的last-create-response/last-payment-response及HTTP状态和时间元数据，只记录响应，不记录请求Authorization/Cookie；SDK只记录resultStatus和截断memo，不记录完整支付回调。下次明确确认支付后，可以区分请求失败、参数无法解析、金额不符及SDK/URL唤起失败。

标准SDK路径和官方qr.alipay.com地址解析都只是代码已接入；实际F2F收银台参数、唤起和付款仍未通过有效订单验收。调查期间没有新建、付款、取消真实订单。


## 0.4.3 支付适配静态核对 — 2026-10-22

本次从应用汇公开下载入口取得 U净现版 APK，仅作静态资源检查，没有安装或执行。AndroidManifest 验证 package=com.midea.vm.washer、versionName=2.4.18、versionCode=20418；文件 107499274 bytes，SHA256 0adcfc7caefbae96c0131db89f09b5fe046c18876eb5b50acdba0dd6db61f691。来源及静态资源保存在 private/ujing-research/current-static/manifest.json；该证据补充了此前只有旧 Cordova 包的限制。尚未独立核验分发包签名与开发者原版的一致性。

现版 assets/washer/cashier.js 的 alipayF2FPay(true) 对应“立即支付”，startPay 把 alipayF2FNoAds 传给 payment/arguments；优惠入口使用 false。pullUpPayModule 将 alipay 与 alipayF2F 分别交给原生模块，iOS F2F 成功分支标记跳转当面付 H5。因此不能把标准 App 支付签名串视作 F2F 的唯一返回格式。安装包同时包含其他容器的 H5 trade_no 支付路径，但未据此猜测本账号返回或拼接支付 URL。

代码变化：F2F 请求明确使用 alipayF2FNoAds=true 对齐“立即支付”；标准 alipay 请求不带该标记，均不带 chooseSign。支付返回先区分只查询、受限 HTTPS qr.alipay.com 收银台地址及校验通过的 SDK 签名串，修复 orderInfo 放二维码地址时被提前误判为签名串的问题。未识别的返回依旧保留交易诊断并提示核对，不能当作付款成功。

没有新增真实预约、调用 payment/arguments、付款、取消或启动设备。上述修复并未证明此前跳转失败的唯一原因；F2F 真实返回及手机端支付仍待正常洗衣时验证。


## 0.4.4 真实 F2F 返回修复 — 2026-10-22

本次手机诊断首次取得真实 payment/arguments 回执：HTTP200/code0，data.url 为 alipays://platformapi/startApp，appId=20000042、followType=PUBLIC、actionType=WebView，内嵌 HTTPS openauth.alipay.com/oauth2/publicAppAuthorize.htm，redirect_uri 指向 wx.zhinengxiyifang.cn/static/commonWasher/index.html。完整交易链接仅保留在 private/payment-failure-*，不在文档或测试发布。没有 last-payment-launch.json，旧代码在解析阶段即拒绝了该 scheme，尚未调用支付宝打开接口。这是本次失败的直接证据。

新版本复用后台签发的完整链接，不拼接、改写授权或交易参数。核心解析与 iOS 打开入口共用白名单校验，限制支付宝 scheme、host、path、App ID、内嵌授权域及 U净回跳地址，拒绝重复参数、伪装域及其他 App。已有 HTTPS QR 与 SDK 签名路径保留。真实返回在本机离线解析验证为 checkout，且 URL 与原文逐字一致。

读取时本人的该笔单脱水订单已经取消；没有重开旧链接、获取新支付参数、创建、取消或支付新订单。0.4.4 修复了解析及打开入口，实际支付宝跳转、授权收银台与支付仍待有效订单验收。


## 0.4.5 连续确认与渠道预查询 — 2026-10-22

用户在 0.4.4 后反馈“现在可以了”，说明其实际跳转已可用；未把该反馈扩展为独立验证扣费或机器启动。

经用户同意，新的核对页把预约及前往支付宝合为一次明确确认，保留金额、可能扣费启动与放好衣物提示。正常创建并核对订单成功才继续付款；若创建异常，即使只读恢复成功也停在订单卡，需重新确认付款。已有未付订单仍有单独付款确认和取消入口。

Provider 只对 payment/methods 做45秒内存缓存：保存订单号后即并行准备渠道，与读取订单详情重叠；同一订单、设备及完整配置下的并发查询复用同一任务，不同订单或凭据不复用。准备失败不阻断预约，实际付款可重新查询。payment/arguments、SDK签名串和支付宝链接均不预取、不缓存、不重放；付款持久化防重标记保持。没有删掉真实链接中的支付宝/U净授权步骤。

本轮仅编译与模拟网络流程验证，无真实交易测速，不对耗时下降幅度作承诺。

## 2026-10-23 正常首次登录证据

用户提供 Stream-2026-10-23 01:09:15.har，共21条请求；仅记录 U净 API 主机。验证码 GET /api/v1/captcha 只带 mobile、type；登录 POST /api/v1/login 只带 captcha、mobile，均HTTP200/code0。没有关闭验证码/风控的参数。登录 data 返回正式token（isTempToken=false）及不同的 id、userId；JWT appUserId对应data.id，JWT id对应data.userId。会话标识与身份值仅留private，不发布。

使用新token、校日常客户端标识和最小业务请求头，只读查询本人已保存机器成功（HTTP200/code0），没有复制官方客户端的Cookie、设备ID或位置，不重放短信或登录验证码。

原生实现正常SMS登录（待本人App内实测），按服务器data.id分区保存机器库，账号与可选设备存储于钥匙串。旧JWT声明只用于已验证登录后保留同一账号的本地机器偏好，不用它授权服务端请求。旧的已完成订单可补归属元数据；未决订单禁止更换账号/设备。

Stream已确认停止记录，并恢复原黑名单模式、关闭临时白名单模式；临时添加的U净域名仍在不启用的白名单中，用户原黑名单未改。官方登录请求和响应不写入公开文档或自动化测试。
