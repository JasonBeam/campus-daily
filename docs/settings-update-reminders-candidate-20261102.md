# 设置与更新提醒候选

本地候选，未发布、未安装。用户手机已按要求恢复 GitHub v0.8.0 build38，安装包 SHA-256 与 Release 资产一致；同一 bundle ID 覆盖安装后，热水会话及洗衣订单文件哈希不变。签名沿用原描述文件，主 App 有效至北京时间 11 月 8 日 21:41:45。

## 设置

iOS、Android 把“洗衣结束提醒”从洗衣页移到设备/设置的“提醒”区，沿用既有开关值、通知权限申请和订单核对逻辑。不开启时不安排提醒；预计结束通知仍需区分真正的服务端完成状态。

iOS 新增“版本更新提醒”（默认开启）及“检查更新”。App 活跃时自动查询 GitHub JasonBeam/campus-daily 最新正式 Release，每次进程内自动检查间隔至少六小时；同一 Release/build 自动提示一次。用户可关闭自动提醒，仍可手动检查。使用公开 GitHub API，不传学校账号或订单。版本按数值比较，仅接受本项目正式 Release 和对应 iOS IPA，支持同版本更高 build，不把低于当前候选的正式版提示为升级。失败显示检查失败；查看更新打开对应 GitHub Release，不自动安装、不宣称 iOS 后台推送。Android 本轮只迁移洗衣提醒位置，尚未加入版本检查。

## 付款后启动：新的调查证据

从实际收银台入口的公开网页加载链取得 U净 H5 资源：

- https://wx.zhinengxiyifang.cn/static/commonWasher/index.html
- https://wx.zhinengxiyifang.cn/static/washer-h5/commonWasher/latest/index.html
- 后者的 assets/js/app.js 中导出 startDevices，使用 GET orders/{orderId}/control/start。
- assets/js/chunk-159e21df.js 中，启动按钮适用于状态 20、35、22；确认前展示衣物/关门等说明。
- confirmStart 按 moduleType 区分路径：1、5 涉及蓝牙；4 涉及 NB/BLE 分支；其他默认分支调用 do2GNBStartWash → startDevices，然后继续核对状态。不能把发现一个接口等同于所有机器都能直接调用。

以上只下载公开静态文件，没有调用启动接口。原始 HAR 只有三条请求，没有启动请求、响应或 WebSocket 内容。当前洗衣订单已经在运行，不会为验证接口再启动或新建订单。

下一步需要核实自有设备的 moduleType、线上状态和官方启动分支，并在用户下一次正常洗衣时验证响应语义。付款回跳不作为已支付证据；未验证前不开放自动“立刻洗衣”。

## 验证

iOS Release/iphoneos build41 编译通过；AppUpdateTests 三项测试通过，涵盖同版本 build 比较、版本数字比较、排除测试版及 Android 包、拒绝其他项目链接。Android Kotlin 编译结果记录在 /tmp/campus-settings-android-20261102.log。未进行安装后的更新弹窗或通知实机验收。
