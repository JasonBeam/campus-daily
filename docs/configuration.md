# 配置与使用

## 普通使用

1. 在 App 中打开「校园登录与宿舍」，使用学校官方页面登录。
2. 返回校日常，核对校园卡余额和门户宿舍信息。
3. 宿舍电费目前需要手动选择电表；自动匹配尚未完成。
4. 首次设置热水时，按 App 提示准备本人合法取得的热水平台参数，并确认宿舍与水控设备。
5. 洗衣功能使用本人 U 净账号登录，再扫描或从照片识别洗衣机二维码。

学校密码和验证码由学校官方页面处理，不要发送给开发者。校园卡、宿舍和登录会话按本人账号保存在设备上。公开安装包不包含作者的热水平台私有参数。

下面的 JSON 字段和导入方式只用于旧版迁移、个人恢复或开发排查；普通新用户无需手工填写。

<details>
<summary>查看旧版配置迁移与开发者说明</summary>

第一版需要导入个人 JSON，不能自动登录校园平台，也不能从其他 App 获取身份。不要向开发者或群聊发送完整 HAR、系统诊断文件、Cookie 或密码。

## 校园卡与宿舍配置（0.2.0）

在「设置 → 校园卡配置」单独导入，与热水配置分开保存在钥匙串。兼容已有校园余额项目的配置字段：

```json
{
  "syscustid": "YOUR_OWN_SYSTEM_CUSTOMER_ID",
  "acc_token": "YOUR_OWN_CAMPUS_TOKEN",
  "areacode": "450010",
  "buildingID": "",
  "custid": "YOUR_OWN_CARD_CUSTOMER_ID",
  "userAgent": "",
  "timestamp": "",
  "dorm_room": "你已确认的宿舍号",
  "campus_version": "v1.1.55"
}
```

`buildingID` 为空时，宿舍显示个人配置中已保存的 `dorm_room`；这是绑定信息，不声称刚从电表接口取得。配置 `buildingID` 后，App 通过已有的电表状态接口读取 `piplineName` 或 `roomName`，多电表时不自动选择。`custid` 可留空，但必须只有一张绑定校园卡才会自动获取。

本机开发配置的宿舍来自已有小组件推送缓存，身份与 token 来自用户自己的既有抓包。没有修改原 Scriptable、ESP32 配置或小组件数据。校园接口固定为学校域名，拒绝跳转，token 不转发给其他域名。

余额展示的是查询结果，以查询时间标注，不将 HTTP 日期或本地查询时间描述成服务端账本更新时间。刷新失败保留旧金额；超过 20 分钟或发生查询错误显示「上次余额」。更换账户、校园卡或宿舍后不会混用其他身份的缓存。

开发安装使用 `Documents/bootstrap.campusconfig` 传入配置；导入钥匙串后移除临时文件。可选 `bootstrap.campuscache` 仅导入 owner 匹配的真实查询结果，不包含 token。

## 热水配置

导入格式与本机验证成功的 Python 原型相同：

```json
{
  "base_url": "https://isv.lxt6.cn",
  "secret": "YOUR_PROVIDER_SIGNING_SECRET",
  "sid": "YOUR_PROVIDER_SID",
  "student_id": "YOUR_OWN_ACCOUNT_ID",
  "school_id": "YOUR_SCHOOL_ID",
  "machine_id": "11223344",
  "ble_name": "YOUR_WATER_CONTROLLER_NAME",
  "type_id": 1,
  "version": 1
}
```

以上全是占位示例，不是可直接使用的配置。`type_id`、`version` 应取自己的已验证请求值，不能照抄示例数字。

## 字段来源

| 字段 | 来源 |
| --- | --- |
| student_id / school_id / machine_id / type_id / version | 自己的授权请求中 `wxcode` 对应字段；使用账户身份，不是授权响应中的临时 studentId |
| sid | 同一授权请求的表单字段 |
| ble_name | 目标水控的蓝牙广播名称；仅有 HAR 一般不足以得到此字段 |
| secret | 与该服务商实际协议匹配的签名配置；不是 Apple 密码，也不是把 HAR 中的 sign 当作 secret |

完整 HAR 本身不保证包含所有配置，尤其不会直接给出签名密钥。不能仅凭旧抓包中的 sign 推导出可用于新请求的密钥。当前只支持既有原型已验证的完整配置迁移；面向其他同学的自动 HAR 提取与登录流程尚未实现。

`machine_id` 是 4 字节十六进制设备编号；读取设备的 20 字节回复后还会再次比对它。结束用的 4 字节标识来自当次授权响应，App 自动保存，用户不需要填写。

## 保存和更换

文件可以使用 `.json` 或 `.waterconfig` 扩展名。导入后配置保存在本机钥匙串。普通导入不会替用户删除“文件”App 里的原始文件，请自行保管。不公开配置文件，也不要把它加入 Git。

有未结算记录时禁止更换配置，避免丢失该记录所需的身份。App 不会导出钥匙串原值。

开发安装可通过 Xcode/devicectl 将自己的配置复制到 App 沙箱 `Documents/bootstrap.waterconfig`。首页启动后只导入该文件，不执行控制；钥匙串保存成功后删除沙箱中的临时文件。不要把 bootstrap 配置作为 App 资源打进安装包。

## U净只读查询（0.3.0）

设置中可导入个人 JSON，字段为 `headers`、`qrCode`、`deviceId`。headers只使用本人的Authorization和官方版本业务头，导入后放入独立本机钥匙串。固定查询phoenix.ujing.online，不接受任意API地址。个人数据不得放入源码、安装包或GitHub。登录过期时重新取得本人配置；不会自动发送短信、登录、下单或付款。

本机开发引导文件为App Documents下的bootstrap.laundryconfig，导入成功后删除。首次查询由用户打开洗衣页触发，正常60秒内复用，手动刷新可立即只读查询。页面时长和价格来自接口，不使用照片内固定价格。

</details>
