# 在线热水接入服务（候选，尚未完成实机验收）

面向校日常的固定接口服务。手机使用本人校园会话核验热水身份，取得限期的本人会话；平台签名参数不进入客户端。不是通用签名、代理或任意接口转发服务。

## 自行部署

需要自己的 Cloudflare 账户及合法取得的平台参数。可使用 Workers 和 D1 免费额度；不要为部署自动升级付费计划。普通使用者无需自行部署，部署者需要维护该服务。

1. 在此目录安装依赖，运行 `npm test`。测试使用虚拟身份和本机内存数据库，不连接真实水控。
2. 运行 `npx wrangler login`，由账户所有者完成授权。
3. 运行 `npx wrangler d1 create campus-daily-access`。复制 `wrangler.example.jsonc` 为忽略的 `wrangler.local.jsonc`，填入自己的 D1 ID。
4. 运行 `npx wrangler d1 migrations apply DB --remote --config wrangler.local.jsonc`。
5. 用 `npx wrangler secret put NAME --config wrangler.local.jsonc` 逐项输入 `WATER_SECRET`、`WATER_SID`、`WATER_BLE_NAME`、`WATER_TYPE_ID`、`WATER_VERSION`、`STATE_SECRET`。不要把值放入命令参数或提交到 Git。STATE_SECRET 应由安全随机源生成，并长期保管；随意更换会破坏账号关联、游标和未决记录的识别。
6. 运行 `npx wrangler deploy --config wrangler.local.jsonc`。首次部署可能需要在本人账户注册 workers.dev 子域名。
7. 核对 `/health`、匿名请求拒绝、本人学校登录及只读宿舍查询；再把两个客户端的接入服务地址改为自己的 HTTPS 地址并重新构建。不得关闭 TLS 检查。

`TRANSACTIONS_ENABLED` 默认且当前生产环境均为 `false`。真实授权和结算必须经过独立现场验收，不能仅因构建或模拟测试通过就启用。请勿创建自动测试去真实授权、结算或重复提交。

## 数据与边界

不保存学校密码、校园会话、姓名或手机号。数据库保留带期限的热水会话（仅存令牌哈希）、账号的 HMAC 关联、本人水控绑定、速率限制和防重操作状态。此版本尚未实现完整的过期记录清理和运营管理界面，部署者需关注免费额度、备份和保留期限。

宿舍游标按账号签名；绑定前核对水控属于所选房间；有未决操作时禁止换绑。授权前先持久化账号锁，不确定结果保留锁，重新登录或进程重启不会解除。固定学校与热水域名，拒绝上游重定向，不提供任意签名端点。

`/v1/bootstrap` 使用已验证会话和门户宿舍地址，一次返回地点层级、唯一匹配路径及水控候选。匹配不明确时停止，不猜测设备，也不执行绑定或授权。公共地点目录使用有大小和时间上限的内存缓存；不缓存身份、校园会话、水控列表或账号游标，每次响应重新签发当前账号的游标。

可在自己的域名上配置 Workers Custom Domain。服务运行在云端，不依赖部署电脑或家庭网络保持在线。付费额度和跨境线路质量是不同问题，升级计划并不能保证校园或移动网络访问更快。

Cloudflare Workers 的 Request 不接受 `redirect: "error"`。本服务使用 `manual` 并拒绝所有非成功响应，防止把身份转发到重定向目标。不要替换成自动跟随。

密钥、账号配置、抓包、日志中的敏感内容及个人设备标识不属于公开示例。此目录只包含占位配置和虚拟测试数据。
