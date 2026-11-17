# 历史订单数据源调查

2026-11-04，只读检查源码及本机 SQLite；未新建、支付、取消或启动任何订单。

## ESP32 dashboard 的记录

已检查 BeamJasonESP 的 web/dashboard/server.py、companion/mac_companion.py，以及 dashboard 本机数据库的表结构和聚合计数。数据库位于 Mac 的 Application Support/BeamJasonESP/dashboard/campus.sqlite3，而非 ESP32 内部订单库。

observations 表存储 power/card 两类余额样本、数值、来源、来源时间、采集时间及缓存状态。没有订单号、交易类型、机器号、单次消费金额等账单字段。当前共有 297 条样本：校园卡 145 条、电费 152 条。部分数据来自 companion_cache，其时间是推送/采集时间，不能视作学校交易发生时间。

因此这批数据可以用于余额历史与走势图，不能转换成真实的每次洗澡消费订单。不能用相邻余额相减反推热水费用。

## 热水消费历史

保存的官方热水小程序使用 getAListOfConsumption 分页查询。此前本人只读查询返回成功但记录为空；该结果不能说明没有消费。

学校一卡通官网的“交易明细”曾在本人手机上实际显示过一笔与本地用水开始时间匹配的热水消费，相关核对记录见 water-delayed-ledger-confirmed-20261102.md。这是下一步优先调查的数据源：核对页面实际查询接口、独立登录要求、字段与分页，再以只读方式展示服务器账单。

尚未验证当前登录有效性，也尚未接入该接口；不得将旧页面验收写成当前接口已打通。

## 洗衣历史

U净公开网页资源中发现 getRunningOrders → orders/running、getHistoryOrders → orders/history；历史页使用 page、size 分页，并使用 orderId、deviceId 跳转详情。网页请求前缀随运行环境变化，与当前原生详情接口路径不完全相同。还需用本人有效登录态核对实际地址和返回字段。

## 界面方向

历史记录展示学校或 U净返回的已结束订单详情；设备控制从热水、洗衣功能页进入。余额趋势单独标为余额记录。本地最近会话、旧未决快照与服务器账单应明确来源，避免把待核对会话呈现为已扣费订单。

当前仅完成数据源研究，未实现完整历史订单功能，未修改或安装 App。
