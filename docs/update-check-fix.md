# 更新检查稳定性修复候选

旧版只请求 GitHub Releases API，匿名请求额度耗尽时返回 403，页面统一显示“暂时无法检查更新”。本机已复现该响应；不能由此认定每台手机的失败原因都相同。

候选 iOS 0.9.0 build53 / Android 0.3.0-alpha26 code28：

- GitHub 接口不可用或返回无效数据时，自动读取本站 Pages 的公开版本记录。
- 保留上次成功结果；离线时标明这是上次记录，不把请求失败当作“已是最新”。
- 检查失败可直接打开下载页；手动检查不受自动检查冷却限制。
- 两个来源都只请求公开版本信息，不发送校园账号或 GitHub 凭据。

这是独立修复候选，未覆盖 v0.9.0 已发布的安装包。旧版 build50 需要先手动安装新版才能使用备用地址；无法远程修改已经安装的程序。

## 发布维护

每次正式 Release 上传并公开后，更新静态备用记录，避免备用信息落后。只提交筛选后的公开文件，不提交完整 API 响应：

```sh
gh api repos/JasonBeam/campus-daily/releases/latest > /tmp/campus-published-release.json
python3 tools/update_release_feed.py --release-json /tmp/campus-published-release.json
```

提交 `docs/updates.json` 后，核对 Pages 已部署、记录版本与 Release 附件一致。草稿与预发布版本不能写入该记录。
