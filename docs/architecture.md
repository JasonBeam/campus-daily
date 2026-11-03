# 校日常 — architecture

How the iOS code is organised and why. Endpoint details (params, envelopes, raw shapes) are in
Appendix A; the Android app in `Android/` is a separate Gradle project that only shares the
school-login script.

Ground rules: the BLE frame format and the `wxcode`/MD5 signing are kept byte for byte; any
change to signing, BLE commands or school/U净 response parsing goes in its own commit with its
reason. Money paths stop rather than guess. The repo never contains real names, ids, rooms,
tokens or the hot-water platform `secret`/`sid`. The hot-water `secret` and `sid` are, however,
built into every public build in plain text (see 2.2).

---

## 1. Module layout

Open `XiaoRiChang.xcworkspace`. It holds `App.xcodeproj` (targets **App** and **Widget**, both
using file-system synchronized folders, so adding a file needs no project edit) and the local
package `Packages/Core`. Debug and Release both use `Configuration/Base.xcconfig` (with
`Version.xcconfig`); a per-developer `Configuration/Developer.xcconfig` (untracked) overrides
team and bundle id.

```
App/
  Application/        XiaoRiChangApp (entry, scene), AppEnvironment (builds the services)
  Interface/<Feature>/ Home, CampusCard, Shower, Laundry, Onboarding, Settings, Location (shared dorm/meter pickers), Common
  Interface/Clear/    清爽's page tree; CampusRootView picks 暖橙's (the feature folders) or 清爽's by theme.
                      ClearRootView is a TabView (日常 / 记录 / 设置), one NavigationStack per tab, routes in
                      ClearRoute and ClearDestination, tab/path/sheet state in ClearNavigator (an environment
                      object). Pages: Home/, Shower/, Laundry/, Records/, Settings/, Setup/ (the first-run
                      checklist). Pages only lay out and call the same models as 暖橙; the shared root
                      handling (reset, first run, refresh, links) is in Common/CampusRootHooks and RootLink.
                      Shared pages (meter, top-ups, 常用洗衣机, 学校账号, 高级, 主题) are 暖橙's views drawn in
                      清爽's tokens.
  Services/           Bluetooth (CoreBluetooth ShowerTransport), CampusWebLogin (official-page WKWebView + login script),
                      BackgroundRefresh (BGAppRefreshTask), Alipay, LiveActivities, Intents, Reminders
  Resources/          Assets, Fonts, Info.plist, App.entitlements
  Demo/               DEBUG-only demo screens and data behind campusdaily://demo/… (not in Release)
Shared/               compiled into App and Widget
  WidgetViews/        widget views (also used by the in-app preview)
  LiveActivityViews/  ActivityAttributes and Live Activity views
  Theme/              formatting and the mascot shape the widget also draws, and the colours the
                      widget and Live Activities need in both themes (ClearPalette, CampusWidgetPalette,
                      LiveActivityAccent); the app's tokens and fonts are in App/Interface/Common
                      (Theme, ThemeColor, ThemeStore, ThemePalette, NativeTheme): the app owns one
                      ThemeStore and injects it; tokens resolve from the view environment (\.appTheme)
Widget/               XiaoRiChangWidget, ShowerLiveActivity, LaundryLiveActivity, Info.plist, Widget.entitlements
Packages/Core/        one library product `Core` (swift-tools 6.0, iOS 17 / macOS 14, Swift 6 mode)
  Sources/Core/
    Campus/           CAS/portal/ecykt session, balance and electricity, meter matching, recharge, SchoolVault + store
    Shower/           lxt6 signed client and signing, BLE frame codec, ShowerEngine + reducer, onboarding, platform profile,
                      ShowerVault + store
    Laundry/          U净 client, order/payment rules, LaundryEngine + reducer, LaundryVault + store, 学校洗衣机 switch
    Snapshot/         the home snapshot ("latest data") and reminder lines shared with the widget, their store,
                      and the refresher (the only writer of the snapshot); the home's two numbers and
                      their low rules (HomeFigures) and the 最近 merge (RecentFeed)
    Networking/       HTTPClient protocol + URLSession implementation, envelopes, redacting logger
    Storage/          generic Keychain and UserDefaults access only: SecureStore, StoreKey, SharedKeychain
                      (app-private and widget-shared access groups), PreferenceStorage, StorageError
    Common/           Money, ServiceError, JSONValue, DormAddress, ShowerHandoff (used by Campus and Shower)
    Theme/            the chosen theme (AppTheme, ThemePreference in the App Group's preferences) and
                      when the 主题 options are greyed out (ThemeLock, from the shower and laundry states)
  Tests/
    CampusTests/ ShowerTests/ LaundryTests/ SnapshotTests/ NetworkingTests/ StorageTests/ CommonTests/ ThemeTests/
    Support/          StubServer, FixtureLoader, FakeShowerTransport
    Fixtures/         synthetic/redacted API samples, one folder per service
Scripts/              fetch-alipay-sdk, stage-water-profile, check-widget-signature, package-ipa, privacy-check
                      (run through mise.toml)
```

Dependency direction (no cycles, nothing imports App):

```
App ──→ Shared ──→ Core
Widget ─→ Shared ──→ Core
Core: Campus / Shower / Laundry ──→ Networking, Storage, Common
      Snapshot ──→ Campus (balances, electricity), Storage
      Theme ──→ Shower, Laundry (their states, read only), Storage
```

Campus never references Snapshot: `SchoolSession.refresh` returns a `SchoolReading` and the
Snapshot refresher reduces it into the shared snapshot.

- Core imports only Foundation, CryptoKit, Security and os: no SwiftUI, UIKit, WidgetKit,
  ActivityKit or CoreBluetooth. Bluetooth is implemented in `App/Services/Bluetooth` behind the
  Core `ShowerTransport` protocol, so tests drive the state machine with a fake transport.
- The three features do not reference each other; shared pieces go in Common. Each feature owns
  its persistence protocol and Keychain store; Storage knows no feature types.
- The widget never touches the shower or laundry state machines; it runs the school refresh
  (`SchoolRefreshStack`, the same one the app builds) and draws the snapshot.
- Only Networking creates URL sessions.

Pure / testable vs platform:

| Layer | Contents | Tested how |
|---|---|---|
| Pure (Common, reducers, parsing) | value types, reducers `(State, Event) -> (State, [Effect])`, parsing, money | plain unit tests, no I/O |
| Clients | request builders + response decoders + error mapping; I/O only through `HTTPClient` | fixture replay via `StubServer` |
| Engines (`ShowerEngine`, `LaundryEngine`, `SchoolSession`) | actors that run reducers, persist before each side effect, call clients/transport through protocols | fakes for transport/store/clock + fixtures |
| Platform (App/Widget) | CoreBluetooth, WKWebView, AlipaySDK, ActivityKit, WidgetKit, BGTask, Keychain access-group entitlement | device/simulator only, kept thin |

Rules: clients are `Sendable` structs, engines are actors, time is injected in Core, only
Networking makes sessions.

**App layer.** The screen models are `ObservableObject` classes passed down
with `@EnvironmentObject`. `ShowerModel.shared`, `CampusModel.shared` and `Reminders.shared` are
singletons (the Live Activity intent, background refresh and notification delegate reach them
outside the view tree); `LaundryModel` is created by the app scene. Core, the App and the Widget
targets all build in Swift 6 language mode.

### Networking

- `ephemeral` sessions, no cookies/cache, redirects **not followed** (a 302 is a response, see
  `getPowerUrl`), timeouts 15 s request / 20 s resource, body cap 64 KiB (1 MiB for campus-wide
  `getMeterStatus`). HTTPS only, default TLS, per-client host allow-list (school hosts,
  `isv.lxt6.cn`, `phoenix.ujing.online`).
- Logging: `os.Logger` with method, host, path, status, latency, decoded `code` only. Query
  strings, bodies and headers are never logged; a `Redactor` masks token/ticket/sign/sid/custid/
  syscustid keys if a DEBUG body dump is needed.
- Error classification (`ServiceError`, in Core/Common):

```swift
enum ServiceError: Error, Equatable, Sendable {
  case offline                     // URLError.notConnectedToInternet, .dataNotAllowed, .networkConnectionLost before send
  case timedOut                    // URLError.timedOut
  case tls                         // URLError.secureConnection*, server cert errors
  case sessionExpired(Service)     // service says the credential is dead (see per-service table)
  case rejected(Service, code: String, message: String)  // service answered "no", with its own words (≤80 chars)
  case badRequest(Service)         // ecykt HTTP 200 + empty body; lxt6 4002 — our params are wrong/stale
  case malformed(Service, String)  // unparseable / missing fields; String = field path, never values
  case uncertain(Service)          // a state-changing request whose outcome we cannot know
}
enum Service: String, Sendable { case cas, portal, ecykt, lxt6, ujing }
```

`uncertain` is produced by engines, not by Networking: any transport error or malformed reply to a
**state-changing** request (authorize, settle, order create, pay arguments, cancel) is
`uncertain`, never `offline`/`timedOut`, so the UI never offers a blind retry.

---

## 2. Services

### 2.1 School: CAS → portal → ecykt

**Login (account and password, native).** `CASLoginClient` drives the CAS password form without a
web view: `GET /cas/login?service=<portal>` (keep the `SESSION` cookie for this one login, read
the form's `execution`), `GET /cas/jwt/publicKey` (PEM), then one `POST /cas/login` with
`"__RSA__" + base64(RSA PKCS#1 v1.5(password))`, `failN=0`, an empty captcha and the install's
random `fpVisitorId`; the redirect is not followed. Its `Location` carries the CAS `ticket`, a JWT
whose payload `idToken` is the **portal token** (with its own `exp`, about 8 h). Then step 2 below.
A refused login with 账号或密码 in the page's `errors` is `wrongCredentials`; captcha, lock,
extra verification, a missing `execution`, a page without errors or any other shape is
`cannotLoginDirectly` (the UI offers the web login). Never retried: 30 failures lock the account.
The password is sent only to CAS, kept only if the user opts in (`school.password`), never logged.

**Login (interactive, WKWebView).** The fallback. CAS uses a JS-encrypted password form; on this
path we never see the password. The app opens the CAS login for the portal service in a non-persistent
`WKWebsiteDataStore`, the user signs in, then:

1. On the portal origin, read `localStorage.token` → **portal token** (`X-Id-Token` JWT).
2. Natively (Networking): `GET portal …/getMyInfo` → dorm address string (`gydz`);
   `GET portal …/getMyECard` → `pcUrl` containing a fresh one-time CAS ticket.
3. Exchange: `POST ecykt /ykt-mini/verify/csalogintoken/{areacode}` `{ticket}` →
   `{syscustid, isbind, token}` → **ecykt token**. Then `getSysBindCustInfo` → bound card
   (`custid`, display name for the owner check).
4. Fallback while step 3 is not verified on device: let the WebView follow `pcUrl` and read
   `localStorage.elecampus_state` on the ecykt origin (what the current app does).

The ticket is single-use and must never be logged; nor may the CAS redirect URL (its JWT carries
personal claims).

**Client surface (`Core/Campus`):**

```swift
struct PortalClient { // X-Id-Token, X-Device-Info: PC, X-Terminal-Info: PC
  func myInfo(_ t: PortalToken) async throws -> DormAddress          // getMyInfo.gydz
  func eCardTicketURL(_ t: PortalToken) async throws -> URL           // getMyECard.pcUrl
}
struct EcyktClient { // POST JSON, acc_token in header AND body
  func exchange(ticket: String) async throws -> EcyktLogin            // csalogintoken
  func boundCards(_ s: EcyktSession) async throws -> [BoundCard]      // getSysBindCustInfo  (VALIDATES token)
  func freshLogin(_ s: EcyktSession) async throws -> EcyktLogin       // loginBySysId        (VALIDATES token)
  func signData(_ s: EcyktSession, custid: String) async throws -> ShowerHandoff // getSignData (VALIDATES)
  func balance(_ s: EcyktSession, custid: String) async throws -> Money        // scanpay/getUserBalance
  func buildings(_ s: EcyktSession, parent: String?) async throws -> [PowerNode] // electricnew/service getBuildingInfo
  func meters(_ s: EcyktSession, nodeID: String) async throws -> [Meter]         // electricnew/service getMeterStatus
  func rechargeWebSession(_ s: EcyktSession, card: BoundCard) async throws -> RechargeWebSession
}
```

**Session model.**

| Credential | Source | Stored | Lifetime (observed) |
|---|---|---|---|
| portal token (`idToken`) + `exp` | CAS login (password form or WebView) | Keychain `school.portal` (AfterFirstUnlock, shared) | about 8 h (`exp`) |
| school account, saved password (opt-in), paused flag | the login form / Settings › 学校账号 | Keychain `school.password` (AfterFirstUnlock) | until sign-out, reset or turned off |
| CAS `fpVisitorId` (random 32 hex per install) | first password login | Keychain `school.device` (shared) | until sign-out or reset |
| ecykt token + `syscustid` + `custid` + `areacode` + UA | exchange / elecampus_state | Keychain `school.ecykt` (AfterFirstUnlock, so BG refresh works) | > 64 min incl. 28 min idle; real TTL unknown |
| dorm address, chosen meter id, building path | portal / user choice | Keychain `school.profile` | until changed |

Facts the design relies on (from the read-only captures):

- Only `loginBySysId`, `getSysBindCustInfo` and `getSignData` validate the token. When it is bad
  they return HTTP 200 `{code:-1, msg:"登录状态已过期，请重新登录！"}`.
- **Do not rely on balance/electricity endpoints to detect expiry**; use the liveness check below.
  (Relying on them produced the current "home is fine, recharge says expired" symptom.)
- HTTP 200 with an **empty body** means missing/undecryptable parameters → `badRequest`, never
  `sessionExpired`.
- `syscustid`/`custid` are re-encrypted on every response. Never compare them for identity; keep
  the value from the latest validating response and use it as input next time.
- `loginBySysId` mints a new token per call and does not revoke old ones; it does not check
  `timestamp`. Do not call it on every refresh (token sprawl); only when building a recharge web
  session (and then use the **fresh** token for `logintoken`, not the old one).

**Refresh algorithm (`SnapshotRefresher.refresh()` → `SchoolSession.refresh()`; the same in the
foreground, the BG task and the widget):**

1. `boundCards` (liveness check). `code:-1` → `sessionExpired(.ecykt)`; go to step 4.
2. On success: `balance`, and `meters(nodeID: savedMeterNode)` in parallel. The session returns
   what it read; the refresher reduces it into the snapshot and stores it. The card records of
   the last three school days (`getRecordList`, same live session, nothing minted) are read
   alongside but never hold the numbers back: they get `CardActivity.timeout` (6 s), land as a
   second write under the same ordering rules, and a slow or failed read keeps the stored ones.
3. Done. Card/power failures are recorded per tile; a liveness failure marks **all** school tiles
   with a "重新登录" state even if old values are shown (values keep their `fetchedAt`).
4. Before minting, `mayMint` renews the cross-process lease (lost → stop, write nothing), and the
   stored session is read again: one the other process stored meanwhile is used instead.
   Silent re-exchange: if a portal token exists and its `exp` (known after a password login) has
   not passed, `eCardTicketURL` → `exchange` → retry step 1 once. Portal `-1001`/`-1` →
   `sessionExpired(.portal)` → go to step 5. A re-exchange with no network is a failed read, not
   「重新登录」, and nothing more is sent. Any other answer that says nothing about the login (a
   timeout, TLS, an unreadable reply, a bare HTTP status such as a 5xx or a 403) also goes to
   step 5: the portal may be down while CAS works, and its token would keep failing until it
   expires. The saved password's hold stops that from repeating; with no password to send, it is
   a failed read. Only a check of the newly exchanged session that gets no answer stops there.
5. Saved password (foreground or background, only if the user chose to save it and it is not
   paused): one CAS login (`CASLoginClient`), then `eCardTicketURL` → `exchange` → step 1. A
   refused login pauses the saved password (`SchoolAccount.paused`) and the UI asks the user to
   sign in again; it is tried again only after the user signs in or saves a password. Once CAS
   accepted it, only a definite refusal of the card login (`sessionExpired`, `rejected` with the
   service's own code, `badRequest`) pauses it; no network, a timeout, a school server error or a
   bare 401/403 is a failed read, and the next refresh exchanges the portal token that login
   stored. The no-answer hold written before the password went out (`unansweredAt`, in the
   shared account item) is lifted only when the login ends with a card session; a failure, a
   lost lease, a sign-out or a cancelled read after the accepted password all leave it, so while
   the portal keeps failing neither process falls through to the password again. A card session
   renewed through the portal token lifts any hold left from an outage.
   No loops, no retries beyond one.
6. The live session (latest ciphertexts, `lastAliveAt`) is written back only while the stored one
   is still the session this read started from: a sign-out or a newer session from the other
   process is never overwritten.

**Credential lifetime log.** `school.ecykt` carries `obtainedAt` (minted) and `lastAliveAt` (last
liveness OK); `school.portal` carries `obtainedAt` (first saved). When the liveness check or the
portal says one is dead, one diagnostic line records only the kind and measured minutes:
`school.credentialExpired kind=card ageMinutes=152 aliveMinutes=92` / `kind=portal ageMinutes=481`
(once per credential per process). Both processes write it to the system log only (subsystem
`org.zaxh.xiaorichang`, category `snapshot`). The `shared.credentialLog` Keychain item
older builds wrote is deleted at launch (`RetiredDiagnostics`) and by reset.

**One refresh at a time.** Callers are pull-to-refresh, the app coming to the foreground,
the background task, the refreshes after a state change (sign-in, meter choice, recharge), and
the widget's timeline. Within a process the refresher runs one read at a time; a caller arriving
while one runs awaits that read and gets its report (pull-to-refresh awaits it, so the "updated"
time or the failure really shows). Exceptions to joining:
- after a state change (`noteChange()`), a caller asking for `includingChanges` does not join a
  read that started before the change: it waits for that read to end, then starts (or joins) a
  read that sees the change;
- when every caller of a read is cancelled (an expiring background task), the read is cancelled
  and writes nothing.
`clear()` (sign-out) empties the snapshot, removes the lease and drops any read still running, so
a late result never writes the old values back. A failed read keeps the last good values and
records the failure and its time per tile.

**One writer across two processes.** The app and the widget extension each have one
`SnapshotRefresher` over one Keychain. They take turns
through `RefreshLease`, the file `refresh.lease` = `{owner, expiresAt}` in the App Group container
(`group.$(APP_BUNDLE_IDENTIFIER)`, read from Info.plist `AppGroupIdentifier`, else `group.` plus
the bundle id the process runs under: `AppIdentity.usableAppGroup`, see 4.2):
- every step (take, renew, check, give back, clear) is one read-compare-write done while holding
  an exclusive `flock` on that file, so two processes never both find the same lease free and a
  holder whose lease ran out never writes over the next one's; the lock is held only for that
  step, never across an `await` (iOS ends a suspended process that holds a file lock in a shared
  container). Only one process reads the school (and may mint) at a time; the other waits up to
  15 s and then reads, by which time the session is fresh, or gives up and shows the stored
  snapshot;
- 180 s long (longer than the slowest chain: liveness, portal exchange, one password login and the
  exchange after it, each up to 20 s, plus the reads), renewed every 20 s while the read runs and
  checked again (renewed) before each step that mints, sends the saved password, saves the new
  portal token or writes the session back; a holder that died leaves it to run out, and the next
  process takes it over in one locked step;
- a read that lost the lease (it ran out and was taken, or a sign-out removed it) stops at the next
  of those steps and writes nothing;
- the card session write-back (refresh, recharge, the hot-water hand-off) and the snapshot save run
  inside that lock (`RefreshLease.withOwnership`, through `LeaseOwnership`): the lease is checked
  and renewed, the stored value compared and the new one written in one locked step, so the other
  process can't take the lease or store its own value in between; the step is synchronous (a
  Keychain write), with no `await` inside the lock;
- every other write of the card session, portal token, saved account or login device id goes the
  same way: the app's logins (the form, 保存密码 / 重新输入密码, the web sign-in) through
  `holdingLease`'s `owning`, and the refresh's saved-password login (its hold,
  its pause, the portal token it brings back). A login compares the stored session, portal token
  and account with the ones it started from and writes everything in that one step; lost lease or
  changed credentials (the app was suspended past the lease and the widget stored newer ones),
  nothing is written and the login reports `busy` (「正在更新，等一下再试。」, the typed password
  stays). A refresh's password accepted after the other process took its lease keeps the hold
  written before it went out, so it is not sent again for a while. Its portal token is still
  written when the lease only ran out (this process is still the stored owner: nobody else took
  it, so nobody else wrote): that step takes the lease again and keeps the owner and compare
  checks; the hold, the pause and lifting the hold are written the same way. A cancelled task (the widget at its deadline) writes nothing, as for every
  other write, and the hold stays. Only deletions skip the lease check: sign-out and
  reset remove the lease first (below), and 保存密码 off removes the password inside the lease
  file's lock without taking the lease (`RefreshLease.locked`), so a refresh's compare-and-write
  of the account never straddles it. A lease file that can't be opened or locked (before the
  first unlock) fails the off instead: the password stays, 学校账号 says
  「密码还存着，没关掉。再试一次。」 and the switch shows on;
- each `holdingLease` call (a login, 保存密码, recharge, the hot-water hand-off) takes the lease
  under its own owner (the process's owner plus `-login-` and a random UUID): two of them at once
  (the login sheet closed and submitted again) take turns like the two processes, and the first
  giving its lease back never releases the second's; each refresh run likewise takes it under
  the process's owner plus `-run-` and a random UUID, so a run whose lease ran out never passes
  the owner check as a later run of the same process;
- a cancelled read (the widget past its deadline) checks for cancellation before taking the lock
  and then writes nothing back, so a process about to be suspended never holds it;
- sign-out and reset remove the lease first and wait for its file lock on a background thread,
  never on the app's main thread, before the school items are deleted;
- snapshot writes are ordered: a reading whose `checkedAt` is older than the stored snapshot's is
  dropped (unless more than 30 minutes older: the clock moved back, and the reading is written), and a "nobody signed in" reading leaves an emptied snapshot empty.
- signed without the App Group (no container), the app keeps the lease in its own container
  (`Application Support/refresh.lease`, `RefreshLease.appFile`), so its reads, logins, recharge
  and hand-off still take turns; the widget has no lease file and never takes the lease: it draws
  the stored snapshot, so the two still never read at the same time.

**The widget's own refresh.** `SchoolRefreshStack` builds the school session (with the CAS
password login) and the refresher with its lease, the same in both processes (`role` "app" /
"widget" names the lease owner). The timeline provider (`getTimeline`) runs `WidgetRefresh.run`:
when the Keychain can't be read (before the first unlock after a restart, or an error) it draws
nothing new, keeping the last face, and asks again in 5 minutes (`WidgetStoredData`); no read when nobody is signed in or the snapshot was checked less than 10 minutes ago (the app
just did, or an earlier widget read); else one `refresh(inBackground: true)` through the same
ladder and write path, waiting at most 5 s for the app's lease and giving up after 20 s (the read
is cancelled and writes nothing; the stored snapshot is drawn). Policy `.after(now + 30 min)`.
The state drawn (fresh / stale / expired / never) is `WidgetStatus.freshness(snapshot, account,
now)` in Core, from the stored `fetchedAt`, `needsLogin` and whether a password is saved (a
saved password held off after a login with no answer is stale, not expired: it resumes by
itself); when
the numbers will turn stale by time alone before the next timeline, a second entry switches at
that second (`WidgetStatus.staleAt`). Tap (`WidgetStatus.tap`): expired / never →
`campusdaily://login` (the login step); stale during a no-answer hold →
`campusdaily://settings/account` (Settings › 学校账号 explains the pause); else `campusdaily://home`. Red is only for low electricity. The footer time
(`UpdateTimeText` in Core) is relative to the entry's date: 「22:10 更新」, 「昨天 22:10 更新」,
「10月29日 22:10 更新」, so an old reading never looks like today's.
The time is the oldest of the tiles that show a number (`WidgetStatus.shownUpdated`), so a card
balance read now doesn't make a meter that kept failing look new; staleness still follows the
newest update.
The small stale line keeps one line at full size: 「8:10 · 打开 App 更新」 today, else the day alone
(「昨天 · 打开 App 更新」).

**Electricity resolution.** The automatic lookup (`SchoolSession.matchElectricity`,
`MeterWalk`) walks the directory the manual picker reads, one small `buildings(parent:)` read
per level: campus → apartment → building → floor (when the building has floors) → room, matching
each level by name against the dorm address from sign-in (`DormAddress`). The portal names no
apartment, so the apartment is the one whose buildings include the dorm's. Every level matched
exactly once → read that room's meters (1 row) and bind the room node with its `comAddress`, no
question asked. Several rooms with the dorm's number → `MeterCandidate`s to choose from, each
with its location 「校区 · 公寓 · 楼栋 · 房间」. A level matching nothing or more than one row →
`.stopped(MeterWalkStop)`: the level, the nodes above, its rows and the rows that matched; the
meter page opens there with the matched levels on one line, 「重选」, and the level's list headed
「选校区」/「选公寓」/「选楼栋」/「选楼层」/「选房间」, suggested rows first with 「可能是这个」
(`MeterPageText`). Each read is retried twice with growing waits on a timeout or a lost
connection.
Only room nodes are bound. A campus-node binding saved by an older build counts as no meter: at
launch it is removed from the profile (the dorm stays) and the launch lookup walks to the room;
neither refresh nor the recharge check reads it meanwhile.
The lookup starts at launch, after every sign-in and on 「再找一次电表」, only signed in with no
meter (`MeterLookupGate`), never on return to the foreground or after a refresh. A sign-in
during a running lookup is looked up once it ends; a same-name list or stopped level stays until
the next answer replaces it. A meter picked by hand wins over a late answer, a dorm changed
meanwhile drops the answer and looks again, and a sign-out or another person drops it.
In a same-name list each row is titled by the first location level that differs among the
candidates (`LocationNaming.titles`), with the full location under it. Every binding keeps that
location (`MeterBinding.location`; floors are left out of picker paths); Settings shows it, and the dorm row uses it when it is the same room
(`SchoolProfile.dormLocation`), else the portal address. Daily refresh queries the room-level
node only (1 row). A meter the school replaced keeps the room node but gets a new `comAddress`:
when the bound node answers with one row under the room's name, the refresh reads that row and
moves the binding to its `comAddress` (`MeterMatcher.pick`, one locked compare-and-write under
the lease); several rows, another room's name or none read as no meter and leave the binding.
`data` is a JSON **string**; all numeric fields are strings → parse with `Decimal` in POSIX locale.

**Error mapping (school):**

| Observed | Maps to |
|---|---|
| ecykt `{code:-1}` from a validating endpoint | `sessionExpired(.ecykt)` |
| ecykt `{code:-1}` from a non-validating endpoint | `rejected(.ecykt, "-1", msg)` (not seen; don't infer expiry) |
| ecykt HTTP 200 + empty body | `badRequest(.ecykt)` |
| ecykt `{code:500, msg:"缺少参数"}` | `badRequest(.ecykt)` |
| ecykt other non-zero `code` | `rejected(.ecykt, code, msg)` |
| ecykt `data:"[]"` for meters | `.success([])` → "没找到电表" in UI, not an error |
| portal `{code:-1001,"无效 token"}`, `{code:-1,"没有访问权限"}` | `sessionExpired(.portal)` |
| HTTP 401/403 from CAS | `sessionExpired(service)` |
| HTTP 401/403 from the portal or ecykt (a gateway or rate limit: both say a dead token with HTTP 200 and a code) | `rejected(service, "HTTP 40x", "")`, not expiry |
| missing `data`/fields, wrong JSON types | `malformed(service, path)` |

### 2.2 Hot water: isv.lxt6.cn + BLE controller

**Platform profile.** `secret`, `sid`, `bleName`, `typeId`, `version` are shared platform
parameters staged into the app bundle at build time from a git-ignored file (`Scripts/stage-water-profile.py stage`, run by the
App build phase). They are not in the repo or fixtures, and the app does not log them, but they are
not secret: every public build carries them in plain text (`CampusWaterPlatform.json` in the
bundle), and `Scripts/stage-water-profile.py fetch` itself takes them from a public IPA. They are
the same for every user, and they alone sign every lxt6 call: authorize and settle sign only
`studentId`, `schoolId`, `machineid`, `machinedata`… (`LxtSigning.operationFields`) with no user
credential. Anyone who extracts them from a build can sign platform calls for any student number;
what such a call charges lands on that student's own hot-water balance. An authorize still needs
`machinedata`, a frame the controller produced in a real BLE session, so the values alone don't
open the water. The read endpoints (areas, rooms, machines) are signable the same way;
`getUserMsg` also needs the `appdata` of the school's ecykt hand-off (`LxtClient.userInfo`), so
it is harder to misuse. This is a platform risk the client cannot fix, accepted as such. The redacted `description`, the
exact-key check on `.waterconfig` files, iOS file protection on the imported copy
(`Application Support/Water/imported.waterconfig`) and its folder kept out of backups
(`ShowerImportFolder`, set before the copy is written and again at launch for older copies) keep
the values out of logs, backups and stray files; they do not protect them.

**Identity hand-off.** `EcyktClient.signData` → `appdata` (`vsuppid, appid, userId, deptId,
username, phone, sign, nonce, timestamp`) → `getUserMsg` (signed, `requestType=1`) → water
`studentid` + `schoolid`. Room/device: `getAreaInfoForApplests` (campus → building → floor),
`getAreaForRoomApplests` (rooms), `getMachineMacAddress` (`machineId`, `Mac`, `machineName`).
Match names against the parsed dorm address (floors use Chinese numerals: `一楼`…).

**Client surface (`Core/Shower`):**

```swift
struct LxtClient {  // signed: wxcode=k=v*_k=v…, sign=md5(secret + formEncode(wxcode)), sid
  func userInfo(_ h: ShowerHandoff) async throws -> ShowerUser             // AECC …/getUserMsg
  func areas(parent: String) async throws -> [AreaNode]                   // getAreaInfoForApplests
  func rooms(floor: String) async throws -> [AreaNode]                    // getAreaForRoomApplests
  func machines(room: String) async throws -> [ShowerMachine]             // getMachineMacAddress
  func authorize(_ c: ShowerBinding, frame: Data) async throws -> ShowerAuthorization // POST, STATE + MONEY
  func settle(_ c: ShowerBinding, frame: Data) async throws -> ShowerReceipt         // POST, MONEY
}
```

Read calls are GET with the signed query; authorize/settle are POST form bodies with the same
three fields. Envelope casing differs by backend: `Code/Data/Message` (AECC) vs
`code/data/message|msg` (zk_*); the decoder accepts both, and accepts a body that is a JSON
**string** containing JSON (seen on `getUserMsg` errors).

**Auth/session.** No user token; requests carry the platform signature, identity is the
`studentid` from the school hand-off. Keychain `water.binding`: `studentId`, `schoolId`,
`machineId`, `roomId`, room label, last peripheral UUID. `getSignData` `-1` → school re-login
(onboarding/rebinding only, not per shower).

**Error mapping (lxt6):**

| Observed | Maps to |
|---|---|
| `code:4002 "参数不匹配"` (bad sign or missing id) | `badRequest(.lxt6)`; if it persists with a known-good request → profile outdated, show "热水配置需要更新" |
| `Code:-301 "…sign 不合法"` | `badRequest(.lxt6)` (same handling as 4002) |
| `code:4034 "查无此信息…"` | `rejected(.lxt6, "4034", msg)` → onboarding shows "学校没有登记这个地址" |
| `code:5000 "当前房间未绑定设备"` | `rejected(.lxt6, "5000", msg)` → "这个房间没有水控" |
| authorize/settle: any other non-zero code | `rejected(.lxt6, code, msg)`. For authorize only 4002/-301 (`badRequest`, `LxtClient.requestRefusalCodes`) prove nothing was issued; every other code, a low balance included (none has been seen), is `authorizeUncertain` and waits for a check |
| authorize/settle: transport error, non-200, unreadable body | `uncertain(.lxt6)` |

Authorize/settle reply shapes and their refusal codes are **not captured**; the
decoders are written from the existing iOS and Android code (`machineid`, `studentId`,
`systemData` hex; settle `pay` in fen) and are verified on device.

### 2.3 Laundry: U净 (phoenix.ujing.online)

**Client surface (`Core/Laundry`):**

```swift
struct UjingClient { // Authorization: Bearer, x-app-code, x-app-version, x-mobile-id, x-mobile-brand, UA
  func requestSMS(mobile: String) async throws                                   // GET /api/v1/captcha  (sends SMS)
  func login(mobile: String, code: String) async throws -> UjingAccount          // POST /api/v1/login
  func scan(qr: String) async throws -> WasherScan                               // POST devices/scanWasherCode
  func programs(deviceID: String) async throws -> WasherInfo                    // GET app/washer/devices/program/info
  func washer(qr: String) async throws -> WasherSnapshot                         // scan + programs
  func createOrder(_ r: OrderRequest) async throws -> String                     // POST orders/create   STATE
  func order(_ id: String) async throws -> LaundryOrder                          // GET orders/{id}/detail?additional=price
  func paymentMethods(_ id: String) async throws -> [PayChannel]                // GET payment/methods
  func paymentArguments(_ id: String, channel: PayChannel) async throws -> PaymentArguments // GET payment/arguments  MONEY
  func cancel(_ id: String) async throws                                         // POST orders/{id}/cancel STATE
}
```

`paymentArguments` returns the raw reply (redacted in descriptions, never stored or logged);
`PaymentLaunchPolicy` turns it into a `PayLaunch` (§3.2). Only the machine-label QR
`https://q.ujing.com.cn/ucqrc/index.html?cd=<18 digits>` is accepted; ids that go into paths
are `[A-Za-z0-9]{1,80}`. Only module type 7 is ordered from the app.

**Auth/session.** SMS login → `{token, id, userId, isTempToken}`; `isTempToken` or a challenge →
`rejected(.ujing, "verification", …)` ("先在 U净 App 里验证一下"). Keychain `laundry.account` plus a
per-install `x-mobile-id` UUID. Expiry: **HTTP 401** `{code:401, message:"Token is invalid" |
"JWT token is missing"}` → `sessionExpired(.ujing)`; no silent refresh, user repeats SMS login
(60 s UI cooldown, never auto-requested). `x-app-code`: `ZI` on captcha/login, `BI` on every
authenticated call (what the existing iOS and Android clients send; not yet verified on a device). `x-mobile-id`
is created once per install and kept in `laundry.account` across logouts. Signed-in calls without
a token fail locally with `sessionExpired` (nothing sent).

**Error mapping (U净):** HTTP 401/403 or envelope `code` 401/403 → `sessionExpired`; envelope
`code != 0` → `rejected(code, message)`; a login challenge message (滑块/风控…) → `verification`.
SMS request, create, payment arguments and cancel are state-changing: transport failure, non-2xx,
unreadable reply or a success without the expected id → `uncertain`. Reads: non-2xx →
`rejected("HTTP n")`, unreadable → `malformed(path)`.

---

## 3. State machines

All engines persist the new state **before** performing the side effect it guards, and treat any
unknown outcome as "may have happened". Reducers live in Core next to their engine and are exhaustively unit-tested.

### 3.1 Hot-water session (`ShowerEngine`)

```
idle ──start──► authorizing ──auth ok──► writePending ──ack 0xAA (9B)──► running
  ▲                │  │                       │                          │
  │      refused   │  │ uncertain             │ user taps 结束            │ user taps 结束
  │◄───────────────┘  ▼                       ▼                          ▼
  │            failed(needsReview)      closing ◄──────────────────────  closing
  │                                         │ state probe 0xA5 → send close cmd
  │                                         ▼
  │                                     settling ──receipt──► done ──► idle
  │                                         │ uncertain/refused
  └──── resolveManually (after user checks official record) ◄── failed(needsReview)
```

| State | Persisted fields | UI | Allowed actions |
|---|---|---|---|
| `idle` | last receipt | 开水 | start |
| `authorizing` | machineId, peripheral | 正在开水… | none (await) |
| `writePending` | + authorizationId, startedAt | **洗澡中**, hint 「水控没回应，有热水就照常洗」 | finish, review |
| `running` | same | 洗澡中 + timer; Live Activity | finish, review |
| `closing` | + close requested | 正在结束… | none |
| `settling` | + consumption frame | 正在结算… | none; on relaunch: show "结算待核对" |
| `done` | receipt (fen, duration) | 本次 ¥x.xx | dismiss → idle |
| `failed(reason, needsReview)` | everything above | reason + 「去看热水记录」 | resolveManually (if needsReview), dismiss (if not) |

Rules:

- Any state but `idle`/`done` blocks `start`. Authorize: definite refusal (refused before
  sending, or 4002/-301) → `failed(needsReview: false)` (nothing issued); anything else, any
  other platform code included → `failed(needsReview: true)`; never re-authorize.
- `writePending` shows as running on purpose (the controller may have accepted without acking).
  `finish` from it: probe shows the device idle with our identity → the check face
  (`stateReviewRequired`, as from `running`: the write may have been applied with only its ack
  lost); `idle` with no charge only when the write provably never reached the controller
  (cancelled before it, or the write refused); `0xA5` → close.
- Close is sent only after the probe returns `0xA5`; otherwise keep the session, flag review.
  A close that never reached the controller (cancelled before the write, the link unusable, or
  the write refused) goes back to the timer, so 结束 sends it again. Only a close lost after the
  write was taken is `failed(closeUnconfirmed)`; from there a read-only review probe is
  allowed (the unsure face's 「再查一次水控」, Settings' 检查水控状态): `0xA5` returns to
  `running` (the close can be sent again), anything else keeps the check.
- Whose session a close ended: the consumption frame is `55`, the machine id (4 bytes) and 15
  bytes whose layout is not known; nothing in it is known to name the authorization or the
  student, so it can't be checked against `authorizationID`. `0xA5` only says water runs, not
  whose. The one reply tied to our authorization is the write's ack (`0xAA`, 9 bytes), so the
  consumption frame is settled by itself only for a session that got it (`running` from the
  ack). Without it (`writePending`, also when a probe later found `0xA5`), and after a probe
  found water running behind an unconfirmed close, the frame is kept (`holdSettle`):
  `failed(settleUnconfirmed)` with the settlement not sent, settled by 「再结算一次」's two taps
  after the user looked. An acknowledged session the controller ended by itself, followed by
  someone else's on the same controller before 结束, is not caught: nothing the controller
  sends tells them apart.
- `settling` is never auto-retried; repeat-settle idempotency is unknown, so a manual retry
  needs a second confirmation and is counted on the record (`manualSettleAttempts`). It is 「再结算一次」 on the unsure
  face of a settlement that failed with its consumption frame kept: the first tap arms it, the
  second sends it.
- A probe that finds the controller stopped under a running record sets `stateReviewRequired`:
  the shower page shows a check face (去核对 / 「我在学校记录里核对过了」) and the home card's
  button reads 去核对. 「再查一次水控」 on that face runs the same read-only probe again: water
  still running returns to the timer; a stopped or unreachable controller is said under it.
- `startedAt` is set when the authorization arrives and enters `writePending` (出水), not at the
  开始洗澡 tap: the ~15 s of connecting and authorizing are not shower time. The in-app timer,
  the Live Activity, the unsettled reminder and the shown duration (done page, settled lock
  screen, 「上次 11 分钟」 and 最近) all count from it; billing uses the controller's consumption
  frame, never a time. Nothing reads the tap time, so it is not kept. A record saved before
  this rule holds the tap time there: past the water it is kept (the timer does not jump back),
  before the water (`authorizing`, or a failure before the authorization reached the controller)
  it is dropped.
- Unsettled reminder after the configured minutes in `writePending/running`. The Live Activity
  mirrors `{phase, startedAt, writeUnconfirmed, amountYuan?}`; its "结束并结算" intent calls
  `ShowerEngine.finish()` in the app process.

### 3.2 Laundry order (`LaundryEngine`)

Local checkout record (one at a time) + server status:

```
none ─confirm─► creating ─id─► created ─付款─► paying ─app returns─► verifying ─paid─► active
                   │uncertain     │  ▲ refused / launch refused │  uncertain ──────►│        │ 40 → Live Activity
                   ▼              │  └───── not paid after polling ◄──────────────┘        ▼ 50/51/53 → none
              reconcile ─adopt─►  │ cancel (unpaid read → one POST → reads)            52 → attention
                   │ none found   ▼                                                        │ acknowledge
                   └─resolveManually─► none   cancelling ─53─► none                        ▼ none
```

Persisted phases: `none, creating, reconcile, created, paying, verifying, active, cancelling,
attention` (Keychain `laundry.checkout`). Relaunch (`LaundryReducer.restore`) never sends
anything: `creating` → `reconcile`, `paying` → `verifying`, `cancelling` before the POST →
`created`; the rest stay.

Server status codes (from current code, not yet verified on a device): `10` reserved/unpaid, `17` unpaid,
`20` paid/waiting start, `21` starting, `40` washing, `50` done, `51` payment timed out,
`52` machine didn't start (check charge in U净), `53` cancelled.

Rules:

- Create only after an explicit confirmation sheet showing machine, program and price, from a
  snapshot (scan + programs) under 60 s old that is still orderable at that price. Payment is
  offered only when `order(id).price` is known and not above the confirmed price (else
  "价格变了，刷新一下").
- `creating` uncertain (or a success without a usable id) → `reconcile`: `scanWasherCode` of the
  same QR gives the account's unfinished `orderId`; adopt it only if `order(id)` matches machine +
  program, was created within 2 min of the local confirmation and is not above the confirmed
  price. Never create a second one. Only when the last lookup found no unfinished order on the
  machine may the user, after checking the U净 app, clear the record (a confirmed 「没有订单，清除」
  on the laundry page); not after a failed lookup, an order that didn't match, or a relaunch
  before a fresh lookup. `createAt` is read as ISO 8601 with an offset, or without one
  (`yyyy-MM-dd HH:mm:ss`, `yyyy-MM-ddTHH:mm:ss`) as Beijing time (the captures only show ISO
  8601 with an offset; the real format is still to be checked on a device).
- The record keeps the U净 account id it was created with. While it is open only that account
  may sign in again (records from before the id was kept compare with the stored login); the
  check runs on the login reply, another account is refused and nothing is saved. The engine is
  rebuilt with the new token and the order read.
- Payment: `payment/methods`, prefer `alipay`, then `alipayF2F` (`alipayF2FNoAds=true`); no
  WeChat and no automatic-debit channel. `paying` (with `paymentRequestedAt`) is persisted before
  `payment/arguments` is sent. The reply is launched only if `PaymentLaunchPolicy` accepts it:
  `https://qr.alipay.com/<code>`; the U净 F2F link `alipays://platformapi/startApp?appId=20000042
  &actionType=WebView&followType=PUBLIC&url=https://openauth.alipay.com/oauth2/publicAppAuthorize.htm?…
  redirect_uri=https://wx.zhinengxiyifang.cn/static/commonWasher/index.html…` (no user/port/
  fragment, no duplicate parameters); or a signed `alipay.trade.app.pay` string for AlipaySDK whose
  `biz_content.total_amount` **equals** the order amount. Any amount parameter in a link (also
  nested) must equal it too. Anything else (other hosts/schemes, `weixin://`, unknown amount)
  is refused and nothing opens. `skipPay`/`jumpToQuery` → poll directly.
- On return (the AlipaySDK reporting back, which also covers its own in-app web page when Alipay
  is not installed, the app becoming active, or after 10 s foreground) poll `order(id)` after 2, 4, 8, 15, 15, 15 s (≈ 1 min);
  still unpaid → back to `created` with "付款未确认". Paid = `payFlag 1` or any non-10/17 status.
- Re-pay only while unpaid (10/17) at the confirmed price, ≥ 2 min after the last payment
  request, with an order read taken after that window and under 5 min old, **and** a second
  confirmation. Never auto-relaunch payment; an uncertain arguments request goes to polling.
- Cancel only from an unpaid `10/17`: fresh read first, then at most one POST (persisted
  `cancelSent` first), then the same polling until `53` or another terminal status. Paid in
  between → no POST.
- Paid but not washing with a known end (`20`, `21`, or `40` with no remaining time): while the
  app is in front it reads the order every 45 s for up to 5 min from that first read
  (`LaundryFollowUp`), and the laundry-done notification is set for the first paid read + the
  program's minutes until a washing read gives the end.
- `40` → Live Activity (machine, program, endsAt) + laundry-done notification at `endsAt`;
  `50`/`53`/`51`/`52` end the activity and the laundry-done notification and clear the record
  (`52` keeps a warning card until acknowledged). `LaundryDoneReminder` decides the notification.

### 3.3 Recharge (card and electricity)

Payment stays inside the school's own web pages (WKWebView); the app does not call the recharge
submit APIs itself (not captured).

```
idle ─tap 充值─► checkingSession ─ok─► webSession ─page loaded─► inPage ─back─► idle
                      │expired                                      │ alipays:// | weixin:// link
                      ▼                                             ▼ open external app
                  renewing (one forced refresh)                 inPage (still)
                      │card read: checkingSession once more
                      │not renewed, or expired again
                      ▼
                  needsLogin (re-login, then retry once)
```

- `renewing`: an expired card session (here or in the hot-water hand-off) is renewed once the
  way home renews it, by a forced refresh (portal token, else the saved password), outside the
  step's lease; when that refresh read the card, the step runs once more
  (`CardSessionRenewal`). The user is asked to sign in only when the refresh did not read the
  card or the second try finds the session expired again.
- `checkingSession`: `boundCards` (liveness) then `freshLogin` → build `elecampus_state`
  `{logintoken: <fresh token>, loginInfo, schoolid, custInfo, custid}` and inject it as a
  document-start user script, ecykt origin only. Card: `/ykt-view/recharge?isbind=1`.
  Electricity: `getPowerUrl?custid&syscustid` (302 → `/ykt-view/powersel?...`; let the WebView
  follow it).
- Navigation allow-list (`RechargeNavigation`): https on `ecykt.`, `portal.`, `cas.` school hosts;
  `alipays`/`alipay`/`weixin` schemes only from a user link tap in the page itself on the ecykt
  origin → `UIApplication.open`. Frames get the same list: a frame on another host is cancelled
  (and logged by host), a frame never opens a pay app, and only `about:blank`/`about:srcdoc`
  (which load nothing) are added for frames. The school login sheet does the same through
  `SchoolLoginNavigation` (three school hosts, https, default port).
- Back from the page, the app claims no result: the next refresh reads the balance and the room
  meter as usual.

---

## 4. Persistence, sharing, identifiers

### 4.1 Stores

| Data | Store | Accessibility | Shared with widget |
|---|---|---|---|
| school credentials (`school.portal`, `school.ecykt`) | Keychain | AfterFirstUnlockThisDeviceOnly | **yes** (the widget renews the card session with the portal token) |
| school profile (dorm, meter) | Keychain `school.profile` | AfterFirstUnlockThisDeviceOnly | **yes** |
| school account + saved password (opt-in) | Keychain `school.password` | AfterFirstUnlockThisDeviceOnly | **yes** (the widget signs in by itself) |
| CAS login device id | Keychain `school.device` | AfterFirstUnlockThisDeviceOnly | **yes** (the widget's login shows the same browser id) |
| water binding, shower session | Keychain `water.binding`, `water.session` | AfterFirstUnlockThisDeviceOnly | never (private group) |
| U净 account, checkout record | Keychain `laundry.account`, `laundry.checkout` | AfterFirstUnlockThisDeviceOnly | never (private group) |
| home snapshot (balances, meter, room label, per-tile error, fetchedAt, needsLogin) | Keychain `shared.snapshot` (≤64 KiB JSON) | AfterFirstUnlockThisDeviceOnly | **yes** |
| reminder thresholds mirrored for widget | Keychain `shared.reminderLines` | same | **yes** |
| credential-lifetime lines from older builds (deleted at launch, never written) | Keychain `shared.credentialLog` | same | **yes** |
| refresh lease (`{owner, expiresAt}`, one school read at a time across processes) | file `refresh.lease` in the App Group container | until first unlock | **yes** (the widget takes it for its own read) |
| reset-in-progress marker (start time) | Keychain `shared.resetMarker` | same | **yes** (any process that can start a shower or a laundry order checks it) |
| UI prefs, reminder toggles, de-dupe state | UserDefaults (standard), keys prefixed `xrc.` | – | no |
| imported hot-water config | file `Application Support/Water/imported.waterconfig`, folder excluded from backup | until first unlock | no |

Reset (Settings › 重置) is all or nothing. It writes `shared.resetMarker` first; while the
marker is under five minutes old, `ShowerEngine.start` and `LaundryEngine.confirmOrder` refuse
with `AppReset.InProgress` (「正在重置」), so neither the app's buttons nor a Shortcut can start
one mid-reset. It then checks the locks once (a shower, a laundry order, an unconfirmed
settlement, an unreadable record). A lock removes the marker and clears nothing (「没有重置」).
Otherwise: school sign-out, clear every item, reload, and the marker is deleted last, only after
a clear that fully succeeded. A marker found at launch means the app was killed mid-reset; the
same steps run again, lock check first, so a shower started after the marker went stale is
left alone and the same alert is shown. A lock found on the second check, after the sign-out,
leaves the user signed out with everything else kept; the shower's Live Activity and its
「还没结束洗澡？」 reminder then follow the shower record (`AppReset.Resync`), and laundry is not
touched.

All Keychain items use service `org.zaxh.xiaorichang.<name>.v1`, account `default`.
Session stores (water/laundry) write synchronously and fail closed: a failed write blocks the
next side effect (`storage` error), same as today.

Widget sharing: App.entitlements lists two keychain access groups, in this order: the app's
private group `$(AppIdentifierPrefix)$(APP_BUNDLE_IDENTIFIER)` (`AppIdentity.keychainGroup`),
then the shared group `$(AppIdentifierPrefix)$(APP_BUNDLE_IDENTIFIER).shared`
Widget.entitlements lists only the shared group. Order matters:
iOS puts an item written without a group into the first listed group, and the code takes the
groups from that default group (`SharedKeychain.sharedGroup(defaultGroup:inExtension:bundleID:)`): the
app's shared group is its default plus `.shared`, the widget's is its default itself. A re-signer
that grants a wildcard (`TEAM.*`) makes each default group the process's own bundle id; the
widget's default then doesn't end in `.shared`, and it uses `TEAM.<bundle id without
.balances>.shared`, the app's (a signature that doesn't allow it falls back to no group). The
first probe of the default group (a throwaway item deleted and added again) is serialised, so two
first uses at once can't make one of them fail. Items marked "yes" are
written to the shared group; all others are written to the private group, which the widget is
not entitled to read. Both work with any signing team incl. free Personal Teams, no portal
registration. The widget reads the school items above for its own refresh, and `shared.snapshot`,
and `shared.reminderLines`, and shares the lease file in the App
Group container. An item can still sit in its old group: builds before the private group existed kept
every item in the shared group, and builds before the widget refreshed by itself kept the portal
token (then WhenUnlocked) and the login device id in the private group. At launch
(`migrateItemGroups()`) and on any read that finds one there, the item is written to its group
with today's accessibility, read back, and only then deleted from the old group; a failed step
keeps the original and retries next launch, so nobody is signed out or loses a binding. The App
Group (`group.$(APP_BUNDLE_IDENTIFIER)`, both targets) holds only the lease file; a re-signed
build without it keeps working: the app keeps its lease file in its own container
(`RefreshLease.appFile`, Application Support, excluded from backup), so its reads, logins,
recharge and hot-water hand-off still take turns, and the widget, which can't open that file,
leaves every refresh to the app, so the two never read at once. Live Activities get data via ActivityKit content
state. Each snapshot write calls `WidgetCenter.reloadTimelines(ofKind:)`; tiles carry their own
`fetchedAt`, and `needsLogin` shows a "需重新登录" badge instead of silently stale numbers.

UserDefaults keys: old `reminder.*`, `water.needsResidenceReview`
become `xrc.reminder.*`, `xrc.water.needsResidenceReview`.

### 4.2 Identifiers

| Item | Value |
|---|---|
| App bundle id | `org.zaxh.xiaorichang` (Android keeps `applicationId` `com.beamjason.xiaorichang`) |
| Widget extension | `org.zaxh.xiaorichang.balances` |
| App Group | `group.org.zaxh.xiaorichang` |
| Keychain access groups | app: `$(AppIdentifierPrefix)org.zaxh.xiaorichang`, then `$(AppIdentifierPrefix)org.zaxh.xiaorichang.shared`; widget: the shared one only |
| Keychain services | `org.zaxh.xiaorichang.<name>.v1` |
| BG task id | `org.zaxh.xiaorichang.refresh` |
| Widget kind | `XiaoRiChangBalances` |
| Alipay return scheme | `org.zaxh.xiaorichang.alipay` (derived, see below) |
| Navigation scheme | `campusdaily://home`; `campusdaily://demo/<state>` in DEBUG builds only |
| Xcode workspace / project / targets | `XiaoRiChang.xcworkspace` / `App.xcodeproj` / `App` (product `XiaoRiChang.app`), `Widget` (product `XiaoRiChangWidget.appex`) |
| Swift package / product | `Packages/Core` / `Core` |
| Display names | 校日常 / widget gallery title 校日常 |

The App Group, the keychain groups and the BG task id are not written into the code: both
entitlements files and both Info.plists are filled from `APP_BUNDLE_IDENTIFIER` at build time
(Info.plist keys `AppGroupIdentifier` = `group.$(APP_BUNDLE_IDENTIFIER)` and
`KeychainGroupIdentifier` = `$(APP_BUNDLE_IDENTIFIER)`, read by `AppIdentity`; the widget carries
the app's values, not its own bundle id; `BGTaskSchedulerPermittedIdentifiers` =
`$(APP_BUNDLE_IDENTIFIER).refresh`). The table shows the values for the default bundle id. iOS
builds before it used `com.beamjason.xiaorichang` for all of these; nothing is migrated, so the
new id installs as a separate app and the user signs in once. A build
with another `APP_BUNDLE_IDENTIFIER` (Developer.xcconfig) gets its own groups; the Keychain service
names stay `org.zaxh.xiaorichang.<name>.v1` in every build. An IPA re-signed under another
bundle id keeps the old Info.plist values: the keychain groups still follow its signature (above),
and the App Group falls back to `group.` plus the bundle id it runs under (the widget's without
`.balances`) when the Info.plist one has no container.

Distribution is an unsigned IPA the user re-signs (`Scripts/package-ipa.py`); there is no App
Store/TestFlight record. Paid-team signers register `org.zaxh.xiaorichang` and
`.balances`; free Personal Teams count them toward the 10 App IDs / 7 days limit.
`Scripts/check-widget-signature.py` checks a signed build before installing.

**Alipay scheme notes.** (1) AlipaySDK `payOrder(_:fromScheme:)` (laundry signed order) returns
to `<scheme>://safepay…`; Info.plist declares `$(PRODUCT_BUNDLE_IDENTIFIER).alipay`, so it
follows the rename. Keep the runtime lookup of the declared scheme ending in `.alipay` (re-signing
tools may change the bundle id after build) and forward only `<scheme>://safepay` URLs to the SDK.
(2) Checkout URLs (`alipays://`, `qr.alipay.com`) and the school page's `alipays`/`weixin` links
open the external app with no return URL, hence the polling/confirming states. Keep
`LSApplicationQueriesSchemes` = `alipay, alipays, alipayqr`. Nothing ties payment to an
Alipay-registered bundle id (the SDK only needs the return scheme); verify on device with one real
laundry payment.

---

## 5. Testing strategy

**Harness** (`Tests/Support`): `FixtureLoader` reads `Packages/Core/Tests/Fixtures/<service>/<name>.json`
(`{request, response:{status, headers, body}, _fixture}`; `body` is an object, a string, or `""`).
`StubServer` (a `URLProtocol`) matches method + host + path (+ body keys like `server`, `buildingID`), replays
status/headers/body, records requests for assertions (`acc_token` in header and body, `wxcode`
field order, no `timestamp`), fails on unmatched requests, and can inject `URLError`s (offline,
timeout, TLS). Plus `FakeBLETransport` (scripted frames, delays, drops), `FakeClock`, in-memory
stores with injectable write failures.

Every endpoint gets at least: success, expired/unauthorized, refused with message, malformed
(derived in-test from a good fixture by deleting a key or changing a type).

**Fixture coverage:**

| Path | Fixtures |
|---|---|
| ecykt liveness ok / expired | `getSysBindCustInfo-ok`, `-badToken` |
| fresh login (recharge) ok / expired / bad params | `loginBySysId-mintSeries1`, `-mintSeries2`, `-badToken`, `-missingSyscustid` (empty body → badRequest) |
| balance (incl. "no expiry signal here") | `getUserBalance-ok`, `-missingCustid` (empty body → badRequest) |
| electricity tree / meters | `electric-getBuildingInfo-root`, `-level1..4`, `-leafEmpty`; `electric-getMeterStatus-ok` (campus), `-leaf`, `-room`, `-unknownBuilding` (`[]`); `electric-service-missingServer` (500) |
| electricity web entry | `getPowerUrl-ok` (302 not followed) |
| water hand-off | `getSignData-ok`, `-badToken` |
| recharge web session state | `localStorage-elecampus_state-csaLogin` |
| card records (最近, 昨天花了) | `card-getRecordList-ok` |
| portal | `getMyInfo-ok`, `-badtoken` (-1001), `-notoken` (-1), `getMyECard-ok` |
| lxt6 reads | `getUserMsg-ok`, `-badSign` (-301, JSON-in-string); `areaInfo-level0..3`, `-badSign` (4002), `-unknownParent` (4034); `getMachineMacAddress-ok`, `-unknownRoom` (5000) |
| U净 auth errors | `ujing/programInfo-noAuth`, `orderDetail-badAuth` (401 shapes, captured); `scanWasherCode-badAuth`, `orderCreate-badAuth` |
| U净 (synthetic, shapes from the existing app) | `captcha-ok`/`-refused`; `login-ok`/`-tempToken`/`-challenge`/`-refused`; `scanWasherCode-ok`/`-activeOrder`/`-refused`; `programInfo-ok`/`-refused`; `orderCreate-ok`/`-refused`; `orderDetail-unpaid`/`-paid`/`-washing`/`-done`/`-failedStart`/`-cancelled`/`-refused`; `paymentMethods-ok`/`-refused`; `paymentArguments-f2f`/`-sdk`/`-skipPay`/`-refused`; `orderCancel-ok`/`-refused` |

Fixture consistency: `portal/getMyInfo-ok`, `lxt6/areaInfo-level3` and
`lxt6/getMachineMacAddress-ok` share one faked dorm, so dorm → room → machine matching runs end to
end; the `piplineName` match test appends one synthetic meter row in-test.

State machines (ShowerEngine, LaundryEngine) are tested with scripted fakes for every
transition in §3, including: crash/relaunch in each persisted state, store write failure,
cancellation between persist and side effect, refusal vs uncertain on authorize/settle/create/
pay/cancel.

**Open gaps.** There is no live capture session. Money and state-changing paths are written
from the existing iOS implementation and the Android code as reference, then verified on the
maintainer's device:

| Gap | Closed by |
|---|---|
| hot water `bathingConsumptionAuthorization` success + refusal shapes | decoder from the existing iOS/Android code; on device |
| hot water `analysisOfBathingConsumptionData` success (+ whether a repeat is idempotent) | decoder from existing code; on device; settle is never auto-retried until then |
| U净 SMS captcha + login (incl. `isTempToken`/challenge), scan, program info, order detail, payment methods, create → pay → status 20/40/50, cancel from 10/17 | client from existing code; on device |
| card recharge submit | not needed: recharge stays in the school's web page |
| electricity recharge order | not needed: recharge stays in the school's web page |
| `csalogintoken` ticket exchange | shape taken from the official page's JS (synthetic test fixture); `adoptWebState` fallback; on device |
| token lifetime: ecykt at +2/+6/+24 h idle; portal token lifetime | scheduled read-only probes (`getSysBindCustInfo`); no user session needed beyond one sign-in |

Decoder tests for the hot-water authorize/settle and U净 paths use synthetic replies shaped like the existing code expects and are
marked as such; no release ships a money path whose device check is still open. `swift test`
touches no network, Bluetooth or host Keychain.

---

## Appendix A. API notes

Recorded with read-only requests only. Redacted fixtures live in
`Packages/Core/Tests/Fixtures/<service>/<endpoint>-<case>.json`, each
`{request:{method,url,headers,body}, response:{status,headers,body}, _fixture:{…}}`.

**Redaction rules.** Tokens, signatures, nonces, CAS tickets, `pcUrl`/`appUrl`, ticket-bearing
`Location` values and the hot-water `sid` are `REDACTED_TOKEN_n` (same value → same number
across fixtures). Personal identifiers (`syscustid`, `custid`, `custunionid`, name, `idno`,
phone, `studentid`, `userId`, `deptId`, `vsuppid`, appid, `headurl`, `voucherno`, meter
`comAddress`, water `machineId`/`Mac`/`machineName`, portal `gydz`/`szbj`) are fake values. Numeric
ids and ciphertexts use shapes no real value has, so `Scripts/privacy-check.sh` can allow them by whole value: zero-padded
counters (`TESTid` + 26 digits, meter `000000000991`), numeric ids starting with `99` (dorm
building ids `991001…`, hot-water area ids `997…`, room `991000000000000002`), or a few fixed
placeholders listed in the script. Dorm data is synthetic: the faked user room is
`星湖校区99栋9号1层991房` (meter `99栋991`, water room `991`), and the room/building lists around
it are synthetic, as are all meter readings and balances (the campus-wide meter list
`electric-getMeterStatus-ok` is 12 invented rows). Lists longer than 12 entries are cut to 12
(`_fixture.truncatedLists` keeps the original length). A `_fixture.synthetic` note in a fixture
names the parts that were replaced with invented data. Captures of a bad token still returning data are not kept in the repo.

Legend: **RO** read-only, **ST** changes server state, **$$** spends money.

### A.1 Login chain

1. CAS (`cas.gdbtu.edu.cn/cas/login?service=<portal>`) is a username/password form; the
   password is encrypted by the CAS page's JS. It redirects to the portal with a `ticket`
   (a JWT whose claims identify the student: never log that URL).
2. The portal SPA turns the ticket into `localStorage.token`. Portal calls send it as
   `X-Id-Token`, plus `X-Device-Info: PC` and `X-Terminal-Info: PC`.
3. `GET /portal-api/v2/personalData/getMyECard` returns `data.pcUrl`/`appUrl`:
   `https://ecykt.gdbtu.edu.cn/ykt-view/authcsatoken?areacode=450010&redirect=…&ticket=…`, with a
   fresh one-time CAS ticket on every call.
4. The ecykt page calls `POST /ykt-mini/verify/csalogintoken/{areacode} {ticket}` (no
   `acc_token`) → `data = {syscustid, isbind, status, token}`, then writes
   `localStorage.elecampus_state = {logintoken: token, loginInfo: {...data, csa:1}, schoolid, custInfo, custid:null, …}`
   (`custInfo` from `getSysBindCustInfo`; see `ecykt/localStorage-elecampus_state-csaLogin`).
   The CSA `loginInfo` has no `timestamp`, so no `timestamp` is sent anywhere.
5. Every ecykt call: `POST` JSON to `https://ecykt.gdbtu.edu.cn/ykt-mini`, `acc_token` in the
   header **and** the body (either alone is accepted).

**Token behaviour.**
- `loginBySysId` ignores `timestamp`, mints a new token on every call, accepts minted tokens
  as input, and does not revoke older tokens. It also returns a re-encrypted `syscustid` each time;
  `getSysBindCustInfo` re-encrypts `custid` each time. All variants are accepted as input:
  never compare these ciphertexts, keep the latest.
- Only `loginBySysId`, `getSysBindCustInfo` and `getSignData` validate the token
  (`code:-1, msg:"登录状态已过期，请重新登录！"`, HTTP 200). Balance and electricity endpoints
  don't signal expiry; use `getSysBindCustInfo` as the liveness check.
- Lifetime: the original token and the first and last of ten minted tokens all still validated
  after more than 1 h, 28 min of it idle (recorded once; no test replays it).

### A.2 ecykt.gdbtu.edu.cn (`/ykt-mini`)

Envelope `{code:int, msg, data}`, HTTP 200, `code 0` = OK. The electricity service returns
`data` as a JSON **string**. A missing or undecryptable required parameter gives **HTTP 200
with an empty body**: treat it as a bad request, never as expiry.

| Endpoint | Validates token | Body (besides `syscustid`, `acc_token`) | `data` | Kind |
|---|---|---|---|---|
| `POST /api/customer/loginBySysId` | yes | `areacode, version("v1.1.55"), appid("wx7077a0b57d156efe"), redirect` | `{syscustid, isbind:1, token}` | RO (mints a token) |
| `POST /api/customer/getSysBindCustInfo` | yes | `areacode, version, appid` | `[{custid, custunionid, custname, idno(masked), areaname, headurl, …}]` | RO |
| `POST /scanpay/getUserBalance` | no | `custid` | yuan number | RO |
| `POST /api/electricnew/service` `server=/api/getBuildingInfo` | no | `areacode, [buildingID]` | JSON string `[{buildingName, buildingID}]`; `[]` at a room | RO |
| `POST /api/electricnew/service` `server=/api/getMeterStatus` | no | `areacode, buildingID` | JSON string `[{comAddress, piplineName("99栋991"), type, meterData, leftMoney, preUseDay, meterStatus, updateDateTime, onlineStatus("在线"/"离线"), price, remaining}]` (all strings) | RO |
| `POST /api/electricnew/service` without `server` | – | – | `code:500, msg:"缺少参数"` | – |
| `POST /api/customer/getSignData` | yes | `custid, timestamp:""` | `{userLoginData, appdata:{vsuppid, phone, appid, sign, deptId, userId, nonce, username, timestamp}}` | RO (hot-water hand-off) |
| `POST /card/getRecordList` | – | `begin, end (yyyyMMdd), custid, datetype:1, pageNum, pageSize, dcflag:"", address:""` | `{total, rows:[{transdate, transtime, transname, amount, balance, dcflag, voucherno, …}]}` | RO |
| `GET /api/electricnew/getPowerUrl?custid&syscustid` | – | – | **302** to `/ykt-view/powersel?interfaceName=powernew_450010&isbind=1` | RO |
| `POST /verify/csalogintoken/{areacode}` | ticket | `{ticket}` | `{syscustid, isbind, status, token}` | login |

Electricity tree (`areacode 450010`): campuses → apartments (`xx公寓`) → buildings (`N栋`) →
floors (`N楼`) → rooms (`NNN`) → `[]`. `getMeterStatus` works at any level (a campus returns
every meter, ≈2.3k rows; a room returns 1). Matching `piplineName == "<栋>栋<room>"` on one
campus-wide read finds the room meter.

Money/state endpoints in the official JS (never called by the app; recharge stays in the
school's web page): `/api/business/balRechargeApply`, `/api/business/balRechargeOrder`,
`/api/business/getOrderSupportPayType`, `/api/pay/wxJsPay`, `/api/electricnew/applyorderid`,
`/api/electricnew/CreateOrder`, card loss/password/bind endpoints, `/api/water/*`.

### A.3 portal.gdbtu.edu.cn

Headers as in A.1. Envelope `{code, message, data}`, HTTP 200.

| Endpoint | `data` | Errors | Kind |
|---|---|---|---|
| `GET /portalData/v2/personalData/getMyInfo` | `{gydz:"示例校区99栋9号1层991房", szbj}` (`gydz` = registered dorm address) | bad token `code:-1001 "无效 token"`; no token `code:-1 "没有访问权限"` | RO |
| `GET /portal-api/v2/personalData/getMyECard` | `{balance, monthBalance, cardStatus, lastExpenditure[], lastIncome[], appUrl, pcUrl, …}` | same | RO (new CAS ticket in `pcUrl` each call) |

### A.4 Hot water: isv.lxt6.cn

Signed GET: `?wxcode=<k=v*_k=v…>&sign=md5(secret + formEncode(wxcode))&sid=<sid>[&requestType=1]`.
`secret`/`sid` come from the platform profile (see 2.2: not in the repo, but in every public build). Envelope casing differs
per backend: `Code/Data/Message` (AECC) vs `code/data/message|msg` (zk_*); some error bodies are
a JSON string containing JSON.

| Endpoint | wxcode fields | Response | Errors | Kind |
|---|---|---|---|---|
| `AECC/GDBusinessSchool/getUserMsg` (+`requestType=1`) | `schoolid=20021, vsuppid, appid, userId, deptId, username, phone` (from `getSignData.appdata`), `random` | `{Code:0, Data:{studentid, studentid_hex, studentname, mobile, schoolid, joinuserid, …}}` | bad sign: JSON-string `{"Code":-301,…"sign 不合法！"}` | RO |
| `zk_areainfo_api/areaInfo/getAreaInfoForApplests` | `id=<parent>` | `{code:0, data:[{id, name}]}` | `4002 "参数不匹配"` (bad sign / missing id); `4034 "查无此信息…"` (unknown id) | RO |
| `zk_areainfo_api/areaInfo/getAreaForRoomApplests` | `id=<floor>` | rooms `[{id, name}]` | – | RO |
| `ZK_BSRS/bathe/getMachineMacAddress` | `typeId, schoolId, roomId` | `{code:0, data:{objList:[{machineId, ID, Mac, machineName}]}}` | `5000 "当前房间未绑定设备"` | RO |
| `ZK_BSRS/GDBusinessSchool/bathingConsumptionAuthorization` | – | not captured | – | **$$** |
| `ZK_BSRS/GDBusinessSchool/analysisOfBathingConsumptionData` | – | not captured | – | **$$** |

Area names: campuses (`星湖校区`, …), buildings `N栋`, floors `一楼…七楼`, rooms `NNN`.

### A.5 Laundry: U净 phoenix.ujing.online

Headers: `Authorization: Bearer <token>`, `x-app-code` (`ZI` captcha/login, `BI` otherwise),
`x-app-version` (`2.4.18`), `x-mobile-id` (per-install UUID), `x-mobile-brand`, UA. Envelope
`{code, message, data}`. Missing token → HTTP 401 "JWT token is missing"; bad token → HTTP 401
"Token is invalid". Only the 401 replies are captured; every other `ujing/` fixture is synthetic
(shapes from the existing app) until they are checked on device.

| Endpoint | Kind |
|---|---|
| `GET /api/v1/captcha?mobile&type=1` | sends an SMS |
| `POST /api/v1/login {mobile, captcha}` → `{token, id, userId, isTempToken}` | login |
| `POST /api/v1/devices/scanWasherCode {qrCode}` | RO |
| `GET /api/v1/app/washer/devices/program/info?deviceId` | RO |
| `GET /api/v1/orders/{id}/detail?additional=price` | RO |
| `GET /api/v1/payment/methods?orderId&include=alipay` | RO |
| `POST /api/v1/orders/create` | **ST** |
| `GET /api/v1/payment/arguments?channel&orderId&payVersion=1[&branchType][&alipayF2FNoAds=true]` | **$$** (Alipay link / signed order / `skipPay`) |
| `POST /api/v1/orders/{id}/cancel` | **ST** |
