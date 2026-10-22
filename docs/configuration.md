# 个人配置

当前没有统一登录向导，需要分别导入本人有效的 JSON。示例全是占位符，不能直接使用；不要填写别人的身份或设备信息，也不要把配置交给开发者代管。

在首页右上角「设置与个人配置」中分别导入校园卡、热水、U净配置。不要将配置打进安装包。未结算热水或待核对洗衣订单存在时，先核对交易，不通过清除记录更换身份。

## 校园卡与宿舍

```json
{
  "syscustid": "YOUR_OWN_SYSTEM_CUSTOMER_ID",
  "acc_token": "YOUR_OWN_CAMPUS_TOKEN",
  "areacode": "450010",
  "buildingID": "",
  "custid": "YOUR_OWN_CARD_CUSTOMER_ID",
  "userAgent": "",
  "timestamp": "",
  "dorm_room": "YOUR_OWN_DORM_LABEL",
  "campus_version": "v1.1.55"
}
```

身份与 token 必须来自本人已授权的校园会话。可以在本机参考已使用的校园余额配置；不要公开导出内容。没有有效配置时，不要让 AI 编造字段值。

`buildingID` 为空时，宿舍来自本人保存的 `dorm_room`，并非刚查询到的电表数据。配置 `buildingID` 后通过学校电表状态接口读取宿舍名称；多绑定不自动挑选。`custid` 为空时，仅在唯一绑定校园卡的情况下自动取得。

`areacode` 与版本示例用于说明结构，是否适用于本人会话仍需核对。余额标注查询时间，失败保留旧值；不代表服务端账本更新时间。

## 热水

```json
{
  "base_url": "https://isv.lxt6.cn",
  "secret": "YOUR_PROVIDER_SIGNING_SECRET",
  "sid": "YOUR_PROVIDER_SID",
  "student_id": "YOUR_OWN_ACCOUNT_ID",
  "school_id": "YOUR_OWN_SCHOOL_ID",
  "machine_id": "11223344",
  "ble_name": "YOUR_WATER_CONTROLLER_NAME",
  "type_id": 1,
  "version": 1
}
```

`machine_id` 为示例的 4 字节十六进制设备编号，必须更换为本人现场确认的设备。`ble_name` 是该水控的广播名，不能只凭编号猜测。`student_id` 是本人账户身份，不是某次授权响应中的临时标识。`sid`、`school_id`、`type_id`、`version` 应与本人已验证协议一致。

`secret` 是匹配该服务商协议的签名配置，不是 Apple 密码，也不是旧请求里的 `sign`。完整 HAR 不保证包含密钥，不能从一个旧 `sign` 直接推导可用密钥。当前仅支持已具备完整合法配置的迁移，没有自动获取密钥或自动 HAR 转配置工具。缺少必要字段时停在这里，不尝试伪造授权。

结束标识由 App 从当次授权响应保存，无需手工填入。不要重放旧授权数据。

## U净

```json
{
  "headers": {
    "Authorization": "Bearer YOUR_OWN_VALID_UJING_ACCESS_TOKEN"
  },
  "qrCode": "https://q.ujing.com.cn/ucqrc/index.html?cd=YOUR_OWN_MACHINE_CODE",
  "deviceId": "YOUR_OWN_DEVICE_ID"
}
```

当前要求本人 U净有效登录凭据、目标机器的二维码原文和匹配的 `deviceId`。`headers` 如需版本业务头，应来自本人当前官方会话，不照抄他人参数。支持的请求头范围可查看 `Sources/WaterCore/Laundry.swift`，不需要额外收集无关 Cookie。

App 没有内置短信登录或读取其他 App 会话的能力。配置获取需在本人设备及授权范围内处理；不要把完整抓包上传给公开 AI 或发到 Issue。登录失效后通过官方入口重新登录，并在本机更新有效配置。

保存机器信息用于后续查询，不代表所有机型都能直接启动。付款仍走后台签发的官方支付宝路径，不自行拼接付款 URL。

## 保存

配置进入 `WhenUnlockedThisDeviceOnly` 钥匙串。普通文件导入后，「文件」App 的原文件仍需自行保管。开发用 `bootstrap.*` 文件只能放进本人的 App 沙箱，不能作为资源、提交 Git 或附到 Release。订单与诊断目录同样不得公开。
