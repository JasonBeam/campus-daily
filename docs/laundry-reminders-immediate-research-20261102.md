# 洗衣提醒与立刻洗衣研究 — 2026-11-02

本轮检查的是自有校日常源码，不是朋友的 IPA。未连接手机、登录、下单、获取支付参数、付款、取消订单或启动机器；未发布安装包。

## 研究结论

洗衣提醒可以分成两种，产品文案必须区分：

- **预计结束提醒**：从服务端返回的剩余时间安排本地通知，提示“预计洗衣结束，请核对订单”。App 不运行时系统也可投递，但停机、延时、断网都可能使预测失准。
- **已确认完成通知**：只在重新查询本人订单、状态确认为完成时发送。现有代码将状态 50 映射为洗衣完成；51 是支付超时、52 是启动失败、53 是取消，不能把共同的 terminal 属性当作完成条件。

“付款后自动洗衣”尚不能认定需要新增启动接口。现有代码已经支持一次确认后创建订单、核对订单并打开支付宝；也提示付款可能启动机器。已付款等待启动（20）、启动中（21）、洗衣中（40）是不同状态。必须先观察用户常用 4G 机器的正常付款过程，判断它是否本来就由后台自动启动，以及用户说的“预约等待”发生在哪一步。当前源码没有经过验证的独立启动接口，也没有两套已验证的预约/即时下单参数。

因此本轮没有添加一个实际上调用相同接口、却承诺不同启动行为的“立刻洗衣”按钮，也没有猜测修改 create 请求的 type=1。

## 当前代码证据

| 项目 | 位置 | 发现 |
| --- | --- | --- |
| iOS 状态模型 | Sources/WaterCore/LaundryOrders.swift:14 | 有订单号、设备号、付款标记、状态、remainTime、countDown；终态包含失败与取消 |
| iOS 下单 | Sources/WaterCore/LaundryOrders.swift:212 | type=1，包含设备、程序、门店；无当前已验证的即时模式参数 |
| iOS 连续下单付款 | App/LaundryModel.swift:271 | createAndPay 已把创建与支付衔接；支付回调后仍查订单 |
| iOS 页面刷新 | App/LaundryView.swift:85 | 进入、下拉刷新；193 行的延时查询仅针对待付预约倒计时，不是洗衣完成监控 |
| iOS 剩余时间 | App/LaundryView.swift:168 | 显示服务端剩余分钟，尚未安排系统通知 |
| Android 状态模型 | platforms/android/app/src/main/java/com/beamjason/xiaorichang/net/LaundryCheckout.kt:14 | 同样区分 50/51/52/53，并保存 remainTime |
| Android 刷新 | platforms/android/app/src/main/java/com/beamjason/xiaorichang/MainActivity.kt:143 | resume 入口及 Compose 协程每 30 秒刷新相关页面；不是可靠的后台任务 |
| Android 权限 | platforms/android/app/src/main/AndroidManifest.xml | 未声明 POST_NOTIFICATIONS；没有完成提醒接收器/后台调度入口 |

对 App、Android 主代码及工程生成脚本检索，未发现 UNUserNotificationCenter、WorkManager 或已实现的洗衣系统通知链路。不能把 BLE characteristic 的 notification 当作系统提醒。

## 推荐实现方案

1. 首次启用“洗衣提醒”时请求系统通知权限，拒绝后仍可正常洗衣，设置中显示权限状态。
2. 从服务端读到本人订单处于运行状态且剩余时间有效时，保存观察时间、剩余秒数及预计结束时间。保留正常订单持久化和账号/设备匹配校验。
3. 以账号范围和订单号生成稳定通知 ID；同单更新覆盖旧计划，不重复安排。只把机器昵称放进通知，不写 token、手机号、订单原文。
4. 预测通知文案使用“预计结束”；重新联网确认状态 50 后，取消未投递预测通知，并发送去重后的“洗衣完成”。若预测已提醒，可仅更新 App 状态，避免对同一事件响两次。
5. 51/52/53 取消结束预测；查询失败保留最后状态并标明时间，不能改成已完成。未知状态不触发完成通知。
6. iOS 用 UNUserNotificationCenter 安排本地通知，App 回前台时重新查订单并校正；后台刷新仅作补充。若要求锁屏/进程退出后仍按服务端完成事件准确提醒，需要可用的服务端推送支持，不能承诺靠定时轮询实现。
7. Android 通过通知渠道和 Android 13+ 通知权限展示提醒；采用持久后台任务补充状态核对，允许系统延迟。回前台及设备重启后从持久记录恢复，核对权限和待通知状态。Doze、强制停止及厂商后台限制须实测，不能依靠页面上的 30 秒循环保证后台实时性。
8. 不为了提醒调用下单、payment/arguments、取消或设备控制接口。

## 两个洗衣选项应如何落地

- **正常洗衣**：保持现有明确确认、下单、支付与订单核对行为。
- **立刻洗衣**：只有官方流程或正常现场观察证实它与预约模式存在区别后才启用。明确提示衣物已放好、门已关好以及付款后可能立即启动；用户选择属于本单授权，持久化到订单，不从旧订单继承。
- 如后台付款后本来就自动启动，可减少客户端确认/等待动作并显示“付款后自动开始”，但要解释两个选项的实际差别；没有差别时不提供两个虚假模式。
- 如确有独立官方启动操作，需要核实接口、参数、适用模块、设备条件和失败语义。服务端确认已付且本人订单匹配后才考虑单次启动；回调不等于已付。启动响应不确定时只读核对，不重复发控制请求。

## 下一次现场验证所需证据

在用户正常需要洗衣时，记录脱敏事件和时间：确认下单 → 订单建立 → 用户付款 → 订单 payFlag/状态变化 → 实际机器启动。特别观察付款后是直接 21/40、停在 20，还是必须在官方页面操作。核对 remainTime 单位、变化及最终状态 50；现有字段命名与 UI 使用秒不能替代这次现场验证。

若需要用户登录，由用户本人完成；本轮没有为了研究创建测试订单。尚未取得上述新证据，独立启动功能暂不进入实现。

提醒验收需覆盖：运行到完成、取消、启动失败、网络失败、重复查询、权限拒绝、切换账号、重启 App、锁屏、进程终止、Android 重启及强制停止。预测误差和后台延迟单独记录。

## 仓库与验证范围

检查时 release/v0.8.0 HEAD 为 5d05499eb9cdb003e487db027690c318c59333df；origin HEAD 通过 ls-remote 读到 fb71b608cc8d5487141e7947f3e3ffdce2187114。开发目录 campus-daily/main 与 release 目录都有未提交改动，均未覆盖、切分支或同步远端。本轮只新增本报告，没有功能源码改动，因此未运行与改动无关的构建/测试，未制作安装包。

## 平台资料

本轮读取 Apple 官方通知文档及其文档 JSON，确认系统可以在 App 不运行或处于后台时投递预先安排的本地通知；它本身不能证明服务端订单已完成。

- https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
- https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest
- https://developer.android.com/develop/ui/views/notifications/notification-permission
- https://developer.android.com/develop/background-work/background-tasks/persistent-work

Android 通知权限文档已读取，确认 Android 13+ POST_NOTIFICATIONS 运行时权限。持久任务页面一次 curl 可读取，后续 urllib 请求被拒；没有把这次受限抓取当作精确定时或重启行为的充分验证。具体后台调度仍需实现时按目标 SDK 与设备验证。

额度保护：02:30 新日志确认 5 小时窗口已重置为剩余 100%，研究中再次读取为 97%；按本聊天要求，后续长任务在有效新日志显示剩余 ≤5% 时保存进度并暂停。
