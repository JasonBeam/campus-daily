# Changelog

版本记录采用 Keep a Changelog 格式。源码仓库不保存个人签名证书或个人配置；测试安装包通过 GitHub Release 单独分发。

## [Unreleased]

### Added

- Add Settings › 反馈问题 (both themes): a form for what went wrong or what you would like, with up to four screenshots you pick yourself (none by default). It sends the text, the screenshots, the app version and build, the phone model, the system version and the language setting to AirFeedback, and nothing from the school, hot-water or U净 accounts. A failed send says 「没发出去，检查一下网络再试一次。」. Builds without the feedback key (private/distribution/Feedback.xcconfig) have no such row.
- Add 「U净 账号」 at the bottom of 常用洗衣机 while signed in to U净: the phone number as 138****5678 and 「退出 U净」 behind 「退出 U净？」. Signing out keeps the saved machines. While a laundry order is unfinished the button is greyed out with 「还有一笔洗衣订单没处理完，处理完才能退出。」.
- Say 「U净 登录过期了。」 with a 「重新登录 U净」 button on the laundry page (both themes) and on 常用洗衣机 when U净 says the login ran out, on a machine read or an order step.
- Add Settings › 外观 › 主题 with two themes: 暖橙 (the current look, the default) and 清爽 (blue and white on the system grouped look, with the 0.8.0 page layout). Both themes run on the same logic; only the pages differ. A tap switches at once and returns to home; the home-screen widget follows at its next reload and the Live Activities at their next update. While a shower is under way (from 开始洗澡, while it connects and authorizes, until the settlement) or a laundry order is unfinished the options are greyed out with the reason above the footer, and they grey out as soon as one starts with the page open.
- In 清爽, the app opens on three tabs, 日常, 记录 and 设置. 日常 shows 电量和校园卡 with 充电费 › and 充校园卡 ›, the 热水洗澡 and 洗衣 tiles, 继续设置 until first-run setup is done, and as many 最近 rows as fit; on short screens it drops the room line, then the large title, then tightens its cards, so it never scrolls below accessibility text sizes. 热水洗澡 and 洗衣 are pages pushed from their tiles with the main button at the bottom; while the shower connects, settles or waits for a check the page hides its back button and the tab bar. 记录 lists what is still open, then the card's records by day. 设置 opens with 首次设置 and holds 快捷指令 and the version. First-run setup is a checklist (学校账号, 宿舍, 学校洗衣机, 水控) whose button names the next row.

- Show 最近 on the home screen: the card's records from the last three school days merged with the app's own showers and laundry orders, newest first, as many whole rows as fit the screen, so home does not scroll.
- Show the full location 「校区 · 公寓 · 楼栋 · 房间」 of the dorm and the electricity meter in Settings.
- Add a 扫洗衣机 button to the laundry page's navigation bar.
- Ask 「2 个公寓都有 3 栋 108，你住哪个？」 under the dorm in the first-run guide's 「你住哪间」 step when the meter lookup found the dorm's room in several apartments; tapping an apartment binds its meter at once, another tap rebinds. The 电表 page at that stop heads its list with the same question and binds the tapped room. The step also shows 「正在找电表…」 while the lookup runs and, when the school is too slow, 「再找一次电表」 with 「电表先跳过，之后在设置 › 电表里选。」; 「就是这间」 is never held up.
- Check the dorm's hot-water controller in the first-run guide (登录 → 学校洗衣机 → 宿舍 → 核对宿舍的水控 → 好了); the check is read-only and can be left for Settings.
- Show a check face on the shower page when the controller reads stopped under a running shower, with 去核对, 「我在学校记录里核对过了」 and 「再查一次水控」; the home card's button reads 去核对 then.

### Changed

- Move the iPhone app's bundle id to `org.zaxh.xiaorichang`. It installs as a new app: sign in once more, and the old 校日常 can be deleted. Android keeps `com.beamjason.xiaorichang`.
- Draw the row icons on home, 校园卡记录, the laundry page, Settings and the home-screen widget (small and medium) as one set of grey line symbols instead of emoji; they stay grey when a number turns red.
- Look for the dorm's electricity meter one level at a time (campus, apartment, building, floor, room) with small reads instead of one read of every meter on the campus; each read is retried twice on a timeout or a lost connection.
- When a level does not match the dorm exactly once, open the meter page at that level: the matched levels with 「重选」, the level's list headed 「选校区」「选公寓」「选楼栋」「选楼层」「选房间」, and the dorm's likely rows first with 「可能是这个」.
- Bind meters to their room only; a meter bound to the whole campus by an earlier build is removed at launch, keeping the dorm, and looked up again.
- The first-run guide no longer says 「没自动找到电表，去「电表」里选一下。」 under the dorm when the lookup stops; home still says the meter is not found.
- Look for the meter at launch, after a sign-in and on 「再找一次电表」 only, no longer on return to the app or after a refresh.
- When several apartments (or campuses) hold a building of the dorm's name, walk each down to the rooms: the one with the dorm's room is bound without asking; when several have it, the lookup stops with those rooms to choose from, each with its full location.
- When one of those apartments could not be read (the school too slow, no connection), do not take it for one without the room: the lookup ends with 「有个公寓没读完，还分不出是哪间。」 and 「再找一次电表」 (plus 「电表先跳过，之后在设置 › 电表里选。」 in the first-run guide), binding nothing; the 电表 page shows no list then.
- Do not take an apartment whose walk stopped before its rooms (floors not matched, two buildings of the dorm's name, more rooms of its name than are read) for one without the room: nothing is bound, and the lookup stops at the apartments asking 「3 栋 108 在哪个公寓？」 (「校区」 at the campuses), the found rooms binding at a tap and each stopped apartment as a row 「这边没对上，点进去自己选」 with a chevron (no check circle in the first-run guide) that opens the 电表 page where it stopped. A room read without a meter still counts as without the room.
- Title same-named dorm and meter rows by the location level that tells them apart (校区, 公寓, 楼栋 or 房间).
- List 电表 first in Settings › 设备.
- Redesign the first-run guide: one layout on every step, four page dots, and 不用 on the laundry question continues to the dorm.
- Redesign the home screen: the date, the card balance and electricity as two numbers (昨天花了 / 够用约 N 天 underneath, red when running low), an update line, one shower button, the 洗衣 row and 最近. The hero sentence and the bottom dock are gone.
- Read the balance and electricity without waiting for the card records; the records get 6 seconds and arrive in a second write.
- Reorganize the repository by feature: `App/` (Application, Interface, Services, Resources), `Shared/`, `Widget/`, one `Packages/Core` package, `Android/`, `Configuration/`, `Scripts/`. The Xcode project is committed (`XiaoRiChang.xcworkspace`), and routine commands run through `mise`.
- Name the hot-water feature "Shower" throughout the code. User-facing text is unchanged.
- Fold the release notes from `docs/release-*.md` into this file.
- Upgrade note: if you built the app from source with your own `APP_BUNDLE_IDENTIFIER` before this version, you are signed out of the school account once after upgrading and need to type the saved password again; builds with the default bundle id are not affected.
- Hide the guide card on 常用洗衣机 once signed in to U净 with a machine saved, and take 「更新 U净 登录」 out of it.
- Show Settings › 版本 as 「0.8.0 Beta（48）」 on TestFlight and development builds and 「0.8.0（48）」 from the App Store, instead of 「0.8.0（48）· 测试版」 everywhere.
- Set the date on the 暖橙 home in the rounded face of the numbers under it, same size and weight; other page titles keep the serif.
- Set the weekday and dorm line under the 暖橙 home date in the rounded face too.

### Fixed

- Say 「没退出成功，再试一次。」 under 「退出 U净」 when signing out of U净 does not go through (the login can't be written), instead of nothing; the button stays, and the line goes once a sign-out works.
- Let 「扫描机身二维码」 and 「从照片识别」 on 常用洗衣机 answer a tap while signed out of U净: the U净 login opens first and, once it goes through, the scanner or the photo picker opens; cancelling the login stays on the page. They were greyed out without saying why.
- Put the cursor in the code field of the U净 login once the code is sent, so iOS can offer the code from Messages there.
- Go back after 保存为常用机器 or a tap on a saved machine, with a success tap; opened from home's unbound 洗衣 row, land on the laundry page. In first-run setup (both themes) saving the same machine again, or choosing a saved one, also moves on.
- Say what a start waits for when the hot-water engine itself turns it down (the record changed in another process after the app's own check), as the app's own refusal does: for an unclear authorize 「水没开。学校提示：…打开校日常核对一下再开始。」 instead of 「上次结算还没确认」.
- Leave out 最近 on home until its rows are measured, instead of drawing three rows first; a new record not measured yet no longer makes the whole section disappear for a moment.
- Say 「这台手机现在存不了洗衣订单，重启 App 再登录 U净。」 when the U净 login can't read the laundry order record, instead of 「这台手机暂时存不了洗衣订单，重启 App 后再试。」.
- When turning 保存密码 off can't go through (the phone not unlocked since it started, say), keep the switch on and say 「密码还存着，没关掉。再试一次。」 in Settings › 学校账号, instead of removing the password where a widget refresh could write it back.
- Count 昨天花了 by the same rule as each day's total in 校园卡记录: a record of another day whose time can't be read no longer hides it, and a record whose day can't be read hides both, since it may be of that day.
- Show a canteen meal paid with WeChat once, as a canteen expense tagged 「微信支付」, in 校园卡记录 and 最近, and count it once in the day's 花了 and in 昨天花了. The school sends it as two records with one voucher (WeChat's money in and the canteen's payment); they showed as 「−¥」 and an unsigned 「¥」 and hid the day's total. The money-in half is not shown or counted while its partner may still be on a page not read yet; once its day is read through, a lone one shows as money in with 「+¥」. Two alike meals with their own vouchers stay two.
- Do not let pages waiting for the settings sheet to close replace a page opened after them directly.
- Do not let a page asked for while the settings sheet was up (a tapped 「衣服洗好了」) come up after a later widget link (home, 学校账号, login), an account-switch alert or a reset.
- Offer same-named electricity meters (one building name in two apartments) with their full location instead of identical names, and bind the chosen one at room level.
- Do not count refunds, reversals and grants as money spent yesterday.
- Do not send a password login when the other process (app or widget) stored new school credentials meanwhile.
- Do not write a sign-in, a saved password or a password login's token over newer school credentials the widget stored while the app was suspended; the sign-in says 「正在更新，等一下再试。」 instead.
- Keep the school's answer to an automatic password sign-in when the app was suspended past its turn and nothing else signed in meanwhile, instead of showing 登录过期 for hours.
- Let a second sign-in started while one is still running wait for it, so the first one ending does not let the widget read in the middle of the second.
- Count 最近's today and yesterday in the school's time zone, as 昨天花了 does.
- Bind the campus instead of a room when more same-named rooms exist than are read, or when one meter is found in two of them.
- Keep a running shower's Live Activity and reminder after a reset that stopped behind the school sign-out.
- Wait for the widget's refresh before the school web sign-in, and keep a typed password that was not sent.
- Keep the saved password when the same person signs in with the school's web page, so the widget still signs in by itself; a different person still clears it.
- Fill in the saved account in the first-run login, and tick 保存密码 by default only while the account typed is the saved one, so another person's password is not kept unless they tick it.
- Let 取消 tapped while a shower starts wait for the start, and show a refusal instead of closing the page.
- Treat a stored school login that no longer reads as someone signed in: a new sign-in drops their dorm, meter and (web sign-in) portal token and says it could not tell who it was, and 保存密码 is refused until the user signs in again.
- Start the shower timer, its Live Activity, the 「还在计时」 reminder and the shower's minutes when the water starts, not when 开始洗澡 is tapped, so the time spent connecting is not counted.
- Run the Core package tests from the App scheme's App.xctestplan on an iOS Simulator; the workspace now lists Packages/Core, so the plan's test targets resolve instead of failing with no test bundles. `mise run check` runs this plan too.
- Read a shower record saved by another build of the app field by field instead of failing on it. A record that still can't be read says 「读不到热水记录。去学校的热水记录里看看这次扣了没有。」 instead of asking for a restart, ends its 洗澡中 Live Activity and 「还在计时」 reminder, and can be removed with 「清除这条记录」 after a confirmation.
- When 结束 finds the controller idle under a shower whose start was never acknowledged (including a Bluetooth link lost after the write), show the check face instead of dropping the record without a settlement; only a write cancelled before it went out or refused by the controller counts as never sent.
- When our authorization provably never reached the controller and 结束 finds it running, send no close and say 「水控有人在用，没发结束，免得关掉别人的水。」 instead of stopping someone else's water and settling it here. A probe from Settings or 「再查一次水控」 on such a shower says the same instead of showing the timer as if the water were ours, and one that finds the controller idle ends the record as 结束 does.
- When the controller refused the close, go back to the timer with 「还没发出去，没结束。再点一次。」 instead of the unsure face. An unconfirmed close can be checked with 「再查一次水控」; water still running goes back to the timer (the old lock screen result goes, the reminder counts from the return, also after a relaunch), and the next 结束 keeps that water's consumption on the unsure face for 再结算一次 or 我在学校记录里核对过了 instead of settling it. That face says the water read may not be the user's and asks them to settle again only if it was theirs.
- Offer 「再结算一次」 (a second tap sends it; leaving the page takes back the first tap) on the unsure face of a settlement that failed with the shower's consumption kept, instead of only marking it checked. The face says whether the school refused the settlement, it never went out, or no answer came.
- Refuse 结束 (also from the lock screen and Shortcuts) before the water is closed when the build has no hot-water profile, with 「这个版本没带热水配置，热水暂时用不了。」, instead of closing the water with a charge that can't be sent. A profile imported then waits for the launch load and turns 结束 back on once the work in flight is done.
- Keep the user signed in when a Keychain read fails (for example before the first unlock after a reboot); only an item that is really gone means signed out, and a stored card session that no longer decodes asks for a sign-in (the numbers stay).
- Do not ask the user to sign in again when a portal token exchange got no answer: with no network it is a failed read; after a timeout, a school server error or a bare HTTP status the saved password is tried once (without one it is a failed read). When the password is accepted but the portal keeps failing after it, the app and the widget hold off for a few hours instead of sending it on every refresh, also when that read was given up or lost its turn to the other process; the hold ends once the portal works again.
- Pause automatic password sign-in only when the school turns the card login down, not on a timeout, a school server error or a bare 401/403 from the portal or the card system after the password was accepted.
- Keep a card session the widget stored while the app was renewing one, instead of writing the older renewal over it; a cancelled check of the stored card session (or of that one) is an interruption, not a failed read.
- Do not start a school login when the browser id for the login page could not be saved, so two logins never send different ids; the form and Settings › 保存密码 say 「登录信息没存上，再试一次。」 and keep what was typed.
- Keep the U净 SMS cooldown under one fixed key without anything derived from the phone number; keys from earlier builds are removed.
- Offer 「没有订单，清除」 (with a confirmation) on the laundry page when an order's creation was never confirmed and a lookup on U净 found no unfinished order; laundry was blocked until a reset. If a later lookup finds something else, the confirmation closes instead of doing nothing.
- Read U净's order time without an offset (「yyyy-MM-dd HH:mm:ss」 or ISO 8601) as Beijing time when checking an unconfirmed order.
- Keep the U净 login open while a laundry order is open, so the account that placed it can sign in again after its login expired; another account is refused with 「还有一笔洗衣订单没结束，要用下单的那个 U净 账号登录。」. While the laundry record can't be read, no U净 login is accepted.
- Read a paid laundry order that hasn't started washing again every 45 s for up to 5 minutes while the app is open, and set the 「衣服洗好了」 reminder from the payment time plus the program until the wash's real end is known. The reminder is cancelled when the machine fails to start, and kept through a cold launch and the settings toggle.
- A notification tap no longer closes a top-up page or a laundry order being paid, and a tap that launches the app opens its page.
- The reminder prompt no longer shows (and gets used up) while the school sign-in sheet is open.
- Keep reading the dorm's electricity after the school replaced its meter: when the room lists one meter under the room's name, it is read and the binding follows it, instead of showing no reading until the meter was picked again by hand.
- Renew an expired card session once, as home does (portal token, else the saved password), before recharge or the hot-water setup asks to sign in again.
- Keep the consumption of a shower the controller never acknowledged for the two-tap 「再结算一次」 instead of settling it by itself, since the controller's reading does not say whose water it was; a held settlement stays held when its retry is refused or gets no answer, and its face opens with 「水控没确认这次是你开的水，读到的用水可能不是你的。」.
- Count only the platform's two known refusal codes (4002 and -301) as an authorize that issued nothing, and say 「水没开成」 for them (Siri: 「学校没让开水，打开校日常看看。」) instead of 「热水平台没同意开水。」; any other answer to 开水, and an OK whose authorization can't be used, now says 「水没开」, with the school's own words as 「学校提示：…」 when it gave any, instead of the settlement warning, on the page, home, the lock screen and in Siri, and the check before the next start stays.
- Do not fail 结束 or a retry at once with 「和水控的连接断了」 because of a notification the controller sent between operations, or because the previous link's disconnect arrived late, and do not fail a reconnect with 「水控没回应」 when the old link is already down but its disconnect never arrived.
- Siri, Shortcuts and the Live Activity say why a start or an end did not go through (for example 「蓝牙没开，打开后再试。」 or 「这次没能结束，打开校日常再试一次。」), and the start no longer says the water is ready when the controller did not confirm it.
- Let sign-in, recharge and the shower hand-off run in a build signed without the App Group instead of failing as busy (they still take turns with the app's refresh, through a lease file in the app's own container; the widget leaves every school read to the app there), and take the App Group, keychain groups and background refresh id from `APP_BUNDLE_IDENTIFIER`; the default bundle id keeps the values earlier builds used.
- In an IPA re-signed under another bundle id, the app and the widget share school data: the shared keychain group follows the group the signature makes the default (the app's plus `.shared`; the widget's own, or, when a wildcard entitlement makes that the widget's bundle id, the app's `.shared` group) instead of the id in Info.plist, and when the App Group in Info.plist has no container, `group.` plus the bundle id the app runs under (the widget's without `.balances`) is tried. The lease file kept in the app's own container is excluded from backup.
- `Scripts/check-widget-signature.py` also fails a signed build when the app or the widget is not entitled to the App Group named in its Info.plist (`AppGroupIdentifier`), which would leave the widget without fresh numbers.
- Scan a picked washer photo off the main thread, say 「照片里没找到二维码，换一张拍清楚的。」 when it has no code, and give each refusal on the common-washer page its own text instead of 「机器名称最多 40 个字。」.
- Forget the last laundry order's result and note when the U净 account that placed it signs out or another account signs in.
- Read the laundry order as soon as the Alipay SDK reports back, also when Alipay pays in its own web page, instead of after 10 s.
- Show only the 最近 rows that fit on home, and leave out 最近 when not even one fits under its header, instead of three rows that made home scroll.
- Draw the tick of a chosen location in the label colour on the accent, so it stays readable in dark mode.
- Show the last shower's amount on the hot-water screen as 「¥1.32」, as everywhere else, instead of 「CN¥1.32」 on some region settings.
- The reset confirmation no longer lists 「选的主题」: the app has no theme setting.
- The sign-in sheet's close button takes taps in a 44 pt square around its circle.
- Read the laundry order once when the app comes back, not twice.

### Removed

- Remove 「导出热水诊断」 (Settings › 高级 › 热水排查) and every diagnostic record behind it: the hot-water event file, the school credential-lifetime lines in the shared Keychain and the Bluetooth scan note. The app deletes what older builds left at launch.
- Remove 「导出热水诊断」 from the Android app too, with its event file and file provider; a file an older build left is deleted at launch.
- Remove the self-hosted hot-water access service (`services/access`), its client in the iOS app and its preparation script. The Android app in `Android/` still contains its client and is unchanged. Hot-water platform parameters now come only from the bundled `CampusWaterPlatform.json` or a user import. Users who were connected only through the access service see the "platform missing" message and need a build with the bundled parameters or an import.
- Remove the process documents, promotional images and the old project generator; their history stays in Git.

## [0.8.0] - 2026-10-29

### Fixed

- Keep campus-card and electricity refreshes independent of a SwiftUI refresh control's cancellation; concurrent refresh entry points share one read.
- Propagate cancelled school requests without labelling them as network failures or continuing the card-identity fallback.
- Apply the automatic-refresh cooldown only after successful reads, leaving failed or cancelled refreshes immediately retryable.

- Retain the Bluetooth connection after successful authorization, matching the official client lifecycle; disconnect after ending or a failed attempt. The effect on the reported device still requires physical validation.
- Persist an observed inactive-water-controller mismatch so restarting the app keeps the session marked for review.
- Retain compatibility with existing saved sessions and block close/settlement on an inactive reply.

### Added

- Add read-only inspection of the controller belonging to an unresolved session, without authorization, valve or payment actions.
- Add a bounded, identifier-free water diagnostic report and expose the build number in Settings.
- Port the iOS fixes to Android 0.2.0-alpha23 (versionCode 25): persist controller mismatches, retain and reuse an authorized BLE connection, add session inspection and diagnostic sharing, and allow immediate retries after failed or cancelled campus refreshes.

The reported brief dispensing followed by stopping is not yet diagnosed. Physical hot-water behavior still requires on-site verification. The Android package remains an alpha23 debug build; users have reported an Alipay launch issue on HarmonyOS.

### Release notes

校日常是面向广东工商职业技术大学的非官方校园生活 App，可以查看校园卡余额、宿舍电费，并使用热水和 U 净洗衣功能。

📦 [选择设备下载](https://jasonbeam.github.io/campus-daily/) · [下载与校验](https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0)

#### 本次更新

- 改进校园卡与电费刷新，失败或取消后可重试并保留已有数据。
- 调整热水蓝牙连接和异常状态处理，增加只读检查与诊断导出。
- iPhone 包含校园余额小组件；Android 包同步相关修复。

#### 注意事项

- iPhone 提供 build 38 无签名 IPA，安装前需使用自己的 Apple 账号签名。该版本已安装到作者手机，现场业务仍需验证。
- Android 提供 0.2.0-alpha23 debug 测试包。用户已反馈 Android 实机测试通过；本版本也通过单元测试与模拟器测试。
- 用户反馈鸿蒙 6.0 至 7.0 可通过卓易通安装使用，但鸿蒙设备目前无法跳转支付宝。不同设备的兼容性可能不同。
- 短暂出水后停水的原因尚未确认；热水完整授权、出水和结算仍需现场核验。
- 本项目不代表学校或相关服务方。请勿公开账号、验证码、令牌、宿舍或交易信息。安装包包含可被提取的通用热水平台参数。

## [0.8.0-beta.2] - 2026-10-29

### Added

- Add Android 0.2.0-alpha22 (versionCode 24) and unsigned iPhone build 36 test packages.
- Automatically match the school-registered residence to the campus electricity-meter directory, asking the user to confirm when duplicate apartments remain.
- Bundle only the shared water-platform fields into locally built test packages so a first-time user does not need to inspect traffic or import a personal configuration.
- Add Android read-only water-controller inspection and device-identity checks for nearby controllers with the same broadcast name.

### Changed

- Reorganize the README around a short product introduction, device downloads, setup guides, AI help and interface previews.
- Separate the normal school-login setup from legacy configuration import and developer migration notes.
- Keep campus-card, electricity and hot-water cache updates scoped to the active account and residence.

### Security

- Keep personal school sessions, student details, residence, controller identity, transaction records and signing certificates out of the public source and installation packages.
- Document that shared water-platform parameters embedded in the test packages can be extracted.
- Record that real hot-water authorization, dispensing and settlement have not been accepted in this release cycle.

### Release notes

Beta 2 支持通过学校官方登录连接校园卡，读取登记宿舍并匹配电表。热水配置可核对本人身份和宿舍水控，正常首次设置无需抓包或导入个人配置。

Android 测试包为 0.2.0-alpha22；iPhone 测试包为 0.8.0 build 36，包含校园双余额小组件。

📦 [选择设备下载](https://jasonbeam.github.io/campus-daily/) · [下载及校验文件](https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0-beta.2)

📖 [安装与签名教程](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/download.md) · 🔗 [连接与使用教程](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/configuration.md)

✨ [界面预览](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/previews/README.md) · [AI 使用教程](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/ai-guide.md)

#### 本版更新

- 学校登录后读取校园卡和登记宿舍；电表唯一匹配时自动保存，同名公寓需本人确认。
- 热水配置支持核对宿舍和水控编号，Android 可在热水页面进行只读连接检查。
- 校园账号、宿舍或设备变更时保护原有记录，避免旧查询结果覆盖新的选择。
- 使用本人 U 净账号管理常用洗衣机，查询状态、程序和价格。

#### 注意事项

- 这是测试版。Android APK 可按手机提示安装；iPhone IPA 未签名，需要用自己的 Apple 账号签名。Safari 下载 IPA 后不会直接完成安装；免费个人签名通常约 7 天需要续签。
- Android alpha22 已在一台用户设备上确认安装和配置后可用。其他 Android 机型、iPhone 全新用户流程、第三方签名小组件，以及完整热水授权、出水和结算尚未完成验收。
- iPhone build 36 曾在用户设备上覆盖安装并保留余额、宿舍与结算记录；本次发布的重新构建 IPA 未再次实机安装。热水操作可能产生费用，请本人现场核对设备和官方结果。
- 本轮 iOS 核心测试 151 项、Android 单元测试 65 项通过；Android lint 有 43 条提示、无错误。构建与测试结果不能代替真实设备和交易验收。
- 安装包包含可被提取的通用热水平台参数，不含作者的个人账号、宿舍、水控编号、交易记录或 Apple 签名证书。请勿公开自己的密码、验证码、校园令牌、宿舍信息、设备二维码或交易链接。
- 界面预览使用示例数据，展示的是较早 Android 版本，页面细节可能与当前版本不同。

详细情况见[首次使用审查](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/first-use-review-2026-10-29.md)和[配置教程](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/configuration.md)。

## [0.8.0-beta.1] - 2026-10-28

### Added

- Add the Android alpha12 test package, the unsigned iPhone build 29 IPA, and a device-specific download page.
- Read the residence address from the school portal during official campus login.
- Add an AI-assisted setup guide and Android page previews with clearly marked sample data.

### Changed

- Reorganize the README around the project summary, main features, downloads, setup and support links.
- Align the iPhone and Android campus, water, laundry, order and device pages.
- Improve Android dorm matching, BLE scanning and water-controller identity checks.
- Keep electricity-meter selection manual until automatic matching is reliable.

### Security

- Keep personal accounts, campus sessions, water-platform parameters and signing keys out of public packages.

### Release notes

面向广东工商职业技术大学的 iPhone 与 Android 测试版。此次更新完善校园网页登录、校园卡同步、宿舍信息读取和安卓蓝牙流程，并统一两端的日常、热水、洗衣与设备页面。

#### 下载

Beta 1 的旧安装包已停止公开下载。请前往 [Beta 2 下载页](https://jasonbeam.github.io/campus-daily/)或 [Beta 2 版本说明](https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0-beta.2)。下面的内容作为 Beta 1 的历史记录保留。

#### 更新内容

- 使用学校官方网页登录后，校日常可同步校园卡信息和门户中的宿舍地址。
- 安卓版改善学校登录、宿舍匹配、蓝牙扫描和同名水控编号确认。
- 两端统一首页余额、热水、洗衣、订单和设备页面的布局。
- 更换账号或宿舍时清理不匹配的旧绑定，避免沿用其他账户的结果。

#### 已知限制

- **宿舍电表暂时不能自动匹配，请手动选择电表。**校园卡余额同步不是本版已知故障。
- 公开安装包不含作者的热水平台私有参数。首次配置热水时，需要本人合法取得对应参数。
- 本版只面向广东工商职业技术大学环境，不代表学校或相关服务方，也不保证其他学校可用。

#### 检查记录

- iOS：83 项 XCTest 与 41 项 Swift Testing 通过。
- Android：35 项单元测试、5 项流程与界面测试、23 组布局场景及 lint 通过。
- Android alpha12 已在 vivo 上覆盖安装并保留原有数据。安装成功不代表所有现场流程均已验证。
- 本轮没有执行真实热水授权、出水、结算、洗衣下单或付款。涉及实际设备和交易的结果，请以现场设备及官方页面为准。

#### 隐私

请只使用本人账号。不要在 Issue、评论或 AI 对话中公开密码、验证码、Cookie、校园令牌、手机号、学号、宿舍信息、设备二维码或付款链接。

## [Android 0.2.0-alpha3] - 2026-10-27

### Release notes

此次更新对照 iPhone 实图调整日常、热水、洗衣、订单和设备页面，保留浅色/深色主题及按系统能力降级的导航玻璃效果。

#### 下载与安装

下载 `campus-daily-android-0.2.0-alpha3.apk`，在 Android 手机按提示允许安装即可。APK 使用开发测试签名，测试者无需个人开发者证书。后续更新需保持相同签名。

- 支持 Android 6.0 / API 23 及以上；HarmonyOS 4.2 为兼容目标，不支持 HarmonyOS NEXT。
- 三款目标手机（华为 nova 10、vivo X200 Pro、三星 S24 Ultra）尚待实机验收。
- 首次使用需本人账号和配置；公开包没有热水平台密钥，热水需导入个人私有配置。
- Android 桌面小组件暂未包含。iPhone IPA 仍需自行签名。

#### 验证范围

20 项单元测试、23 个模拟器截图场景及导航切换通过；Lint 零错误，APK v1/v2 签名验证通过。模拟器验证不代表真实校园登录、蓝牙开关水、结算、洗衣支付已经在安卓实机通过。

[配置教程](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/configuration.md) · [AI 上手教程](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/ai-guide.md) · [Android 说明](https://github.com/JasonBeam/campus-daily/blob/main/Android/README.md)

请保护自己的账号和配置，不要公开上传令牌、设备二维码或个人数据。

## [0.7.0] - 2026-10-23

### Added

- Add in-app school login, dorm selection and hot-water binding setup.
- Add U净 SMS login, account-scoped washer library, QR scanning and photo recognition.
- Add cancellation flow, auto-refreshing payment progress and faster Alipay handoff.
- Add current UI-flow previews for hot water, laundry and first-time setup.
- Add a release code review and public AI onboarding guide.

### Changed

- Reuse a known CoreBluetooth peripheral for faster repeat hot-water connections.
- Keep the app name “校日常” and the home heading “校园生活”.
- Update release build metadata to 0.7.0 build 22.

### Security

- Continue blocking transaction retries when the result is unknown.
- Keep private platform resources out of the public source and Release assets.
- State clearly that the local signed Debug package must not be redistributed.

### Release notes

校日常是面向广东工商职业技术大学的非官方 iPhone 工具。

我做它的原因很直接：每天都要用的校园卡、宿舍热水和 U净洗衣分散在不同入口里，小程序跳转和无关页面太多。这个版本把常用数据与操作集中起来，也让宿舍热水和洗衣机可以少走几次重复步骤。

#### 这个版本有什么

- 首页查看校园卡余额、宿舍、热水结算记录和常用洗衣机。
- 在学校官方网页内登录，并选择校区、楼栋、楼层和寝室绑定热水。
- iPhone 直接通过蓝牙连接水控，提供「开始洗澡」「结束结算」快捷指令动作。
- 使用本人 U净手机号与验证码登录，扫码或从照片识别洗衣机二维码。
- 保存多台常用洗衣机，查看空闲状态、程序和实时价格。
- 核对订单后跳转支付宝；支持取消符合条件的未付款预约。
- 交易结果未知时保留本机状态，避免自动重复授权、付款或结算。

#### 界面流程演示

仓库内有三组 GIF 和 MP4：热水、洗衣、首次配置。它们是脱敏界面流程模拟，不代表真实出水、扣费或机器启动录像。

#### 下载与安装

Release 资产包含：

- `CampusDaily-0.7.0-build22-unsigned.ipa`：无签名开发包，下载后必须用自己的 Apple 身份签名才能安装。
- `CampusDaily-0.7.0-build22-unsigned.ipa.sha256`：下载完整性校验。
- GitHub 自动提供的源码 zip/tar 压缩包。

这个 IPA 不包含作者的开发签名、设备 UDID、描述文件或共享平台签名参数。使用自己的 Mac/Xcode 或可信的 SideStore/AltStore 流程重签后，才能装到自己的设备。

#### 配置教程与 AI 上手

优先使用 App 内流程：

1. 学校官方网页登录。
2. 选择校区、楼栋、楼层和寝室。
3. U净手机号 + 验证码登录。
4. 扫描洗衣机机身二维码并保存常用机器。

完整教程：

- [配置与使用边界](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/configuration.md)
- [构建与签名](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/build-and-signing.md)
- [AI 辅助上手](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/ai-guide.md)
- [故障排查](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/troubleshooting.md)

#### 当前门槛

- 目前没有 TestFlight；公开 IPA 是无签名开发包，必须自行签名。
- 免费 Apple Personal Team 通常每 7 天要重新签名。
- 需要 macOS、完整 Xcode、可签名 Apple 账号和本人合法取得的学校/U净登录条件。
- 当前重点验证的是我实际使用的一种水控和本校流程，不代表其他学校或所有设备通用。
- 首次热水宿舍读取仍依赖共享平台签名参数。源码不包含该参数；Debug 私测包不能公开分发。稳定公开前还需要服务端签名代理或移除这项客户端依赖。

#### 验证记录

- 0.7.0 build 22：
  - 54 项 XCTest + 37 项 Swift Testing，共 91 项离线测试通过。
  - Debug iPhoneOS 签名构建、Release 不签名构建、Xcode 静态分析均通过。
  - 本地设备包严格代码签名校验通过，未上传 GitHub。
- 本人 0.7.0 实机已完成校园登录、宿舍保存、U净短信登录、常用机器查询和重启持久化检查。
- 未把构建、单元测试或支付跳转等同于真实扣费、水流出水和洗衣机启动。

#### 自行构建

```sh
python3 tools/fetch_alipay_sdk.py
python3 tools/generate_project.py
open CampusHotWater.xcodeproj
```

在 Xcode 中用你自己的 Team 和 Bundle Identifier 签名。不要使用作者的设备、描述文件或本机配置。

遇到问题请先读 [配置与使用边界](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/configuration.md)、[构建与签名](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/build-and-signing.md)、[AI 辅助上手](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/ai-guide.md)和[故障排查](https://github.com/JasonBeam/campus-daily/blob/v0.7.0/docs/troubleshooting.md)。

不要在 Issue 中上传配置、HAR、Cookie、token、手机号、学号、精确宿舍、设备二维码、付款链接或签名文件。

## [0.4.6] - 2026-10-22

### Added

- Prepare the first public source snapshot for the unofficial GDBTU iPhone utility, including campus balance, dorm information, hot-water controls and U净 laundry integration.
- Add setup, signing, AI-assisted onboarding, privacy and troubleshooting documentation.

### Changed

- Use 校日常 as the home-screen name while keeping 校园生活 as the home-page title and retaining the original icon.
- Combine laundry reservation and the Alipay handoff after an explicit review, with durable state retained when the result is uncertain.

### Security

- Exclude personal configuration, captured traffic, signing products and transaction diagnostics from the public snapshot.

[0.4.6]: https://github.com/JasonBeam/campus-daily/releases/tag/v0.4.6
[0.7.0]: https://github.com/JasonBeam/campus-daily/tree/v0.7.0
[0.8.0-beta.1]: https://github.com/JasonBeam/campus-daily/tree/v0.8.0-beta.1
[0.8.0-beta.2]: https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0-beta.2
[0.8.0]: https://github.com/JasonBeam/campus-daily/releases/tag/v0.8.0
