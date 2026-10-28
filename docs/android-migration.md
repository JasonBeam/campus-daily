# Android migration — Native Clear

This port follows the selected **03 原生清爽 / Native Clear** design in
[native-clear-design.md](native-clear-design.md). It uses system fonts, blue actions,
grouped surfaces, independent balance timestamps and 日常／订单／设备 navigation.
It does not use the earlier Nothing/dot-matrix proposal.

## Current Android test build — 0.2.0-alpha12

- Version code 14. School login now follows the official campus-card page and reads the portal residence address for setup suggestions.
- Better room-path matching, BLE scanning and water-controller identity checks.
- Electricity meters still require manual selection; automatic matching is not ready.
- 35 unit tests, 5 flow/UI checks, 23 layout scenarios and lint passed. The alpha12 package was installed over an existing vivo installation with data preserved.
- No water authorization, physical water flow, settlement, laundry order or payment was performed in this release check.

Download the tested package from the [current release notes](release-0.8.0-beta.1.md).

## Methods reviewed and applied

| Source | Applied in this app |
| --- | --- |
| [Google Android Skills: adaptive](https://github.com/android/skills/blob/main/jetpack-compose/adaptive/SKILL.md) | Retained screen state, scrollable content, responsive columns, large-font stacking; no orientation lock. Only stable patterns compatible with this toolchain are used. |
| [Google Android Skills: edge-to-edge](https://github.com/android/skills/blob/main/system/edge-to-edge/SKILL.md) | Activity edge-to-edge, safe drawing/keyboard insets, system-managed icon contrast, resize on IME. |
| [Now in Android architecture](https://github.com/android/nowinandroid/blob/main/docs/ArchitectureLearningJourney.md) | Screen state in a ViewModel, StateFlow, lifecycle-aware observation, separate protocol/network/storage code. |
| [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions) | Nearby devices on API 31+, foreground location permission and location-service check on earlier releases; revoked permission handling. |
| [Official Alipay SDK artifact](https://central.sonatype.com/artifact/com.alipay.sdk/alipaysdk-android/15.8.42) | Pinned official SDK, signed app-pay dispatch on a worker thread; read-back confirmation on return. |

Skills were read as development references. No third-party setup script or
automatic conversion tool was run. Experimental Grid/FlexBox and new Compose
versions requiring a newer Android toolchain were not introduced.

## UI changes

| Before | After | Why |
| --- | --- | --- |
| One long page with inline configuration | Three tabs and separate detail/setup screens | Keep everyday actions clear |
| Basic default Material colors | Native Clear light/dark palettes with high-contrast text | Match the confirmed iPhone design |
| One washer snapshot | Saved washer list, QR import and live state | Avoid repeatedly scanning the same machine |
| Start/settle combined in one home button | State-specific action on the hot-water detail page | Make the next operation explicit |
| Fixed 12-second BLE scan | Verified-address connection, identity read before authorization | Reduce repeated discovery without skipping device checks |
| Configuration held by a Composable | ViewModel plus encrypted, atomic account/dorm settings | Survive rotation and partial-write failures |

## Feature implementation

- School login uses the official HTTPS portal in WebView. The user enters their
  own credentials; pressing 读取登录 reads only the school's authenticated origin.
- Card and electricity queries keep separate cache timestamps and errors. Opening
  the app refreshes when the 5-minute interval expires. Manual refresh is throttled
  to 5 seconds; a failed read keeps the previous value marked as old.
- Electricity binding traverses the server's location list and lets the user
  explicitly select the meter. It is independent of water-controller binding.
- Recharging first validates login/card context with official APIs, then transfers
  that context to the official recharge page. Actual payment remains in that page
  or the payment app.
- Water onboarding requires an imported platform profile or personal waterconfig;
  **the public build contains no platform key or personal credentials**. After
  school login, the app reads the student's identity, lists rooms and lets the
  user choose the returned controller. BLE verification reads the physical ID;
  saving without verification is clearly labeled, and start still checks the ID.
- U净 login, saved washers, live program/state query, explicit reservation,
  explicit Alipay handoff, order refresh, own-order countdown and unpaid-order
  cancellation are implemented. A machine used by someone else is shown as busy;
  no remaining time is fabricated when the device response does not provide it.
- All financial mutations persist an intent first. Timeouts/crashes do not
  automatically repeat reservation, payment arguments or cancellation. Ambiguous
  records remain visible for official reconciliation. App-pay callbacks never
  mark an order paid; server read-back does.
- Recent orders are local recent records, not a full history service. Android
  launcher widgets are not included in this migration.

## Data and compatibility

`minSdk=23`, `compileSdk=36`, `targetSdk=35`. The three pilot targets are Huawei
nova 10 / HarmonyOS 4.2, vivo X200 Pro / OriginOS 6, and Samsung SM-S9280 / Android 16.
These are installation targets; manufacturer-specific BLE, WebView and payment
behavior still require acceptance on each real phone. HarmonyOS NEXT is a
different platform and is not supported by an Android APK.

Credentials, saved QR labels, caches and transaction records use Android Keystore
AES-GCM storage. Account/dorm settings are committed together in one encrypted
record. Existing Android prototype account/water keys are read on migration;
old keys are not erased. A legacy washer snapshot lacking its original QR link
requires scanning again. Encrypted data is excluded from cloud/device transfer
because its hardware key does not migrate with it.

## Build and test

Use **JDK 21** with the pinned Gradle/AGP/Kotlin versions. Android Studio's bundled
JBR 25 is not compatible with the current Kotlin Gradle bootstrap; do not use it
as this project's Gradle JDK. On macOS:

```sh
bash tools/build-android.sh
```

The APK is `platforms/android/app/build/outputs/apk/debug/app-debug.apk`, package
`com.beamjason.xiaorichang.debug`, version `0.2.0-alpha2-debug`. It uses the local
Android debug key. Testers do not need a personal developer certificate; Android
still requires installation consent. Keep the same signing key for updates.

Unit tests cover durable intent ordering, timeout/restart behavior, amount
changes, paid-order cancellation prevention, account isolation, malformed
checkout URLs, nested Alipay redirects and official-session parsing. Lint checks
permissions and API use. Debug-only PreviewActivity renders the same screen
composables with clearly labeled fixture data and inert actions; it contains no
repository/network client and is absent from release builds.

Real-device acceptance must include school login, meter/room selection, physical
water-controller identification, authorization and settlement, QR scanning,
reservation, Alipay launch/return and cancellation. A build or emulator screenshot
does not count as that acceptance.

## UI alignment and glass update — 2026-10-27

Version code 4 / 0.2.0-alpha2-debug aligns the main screens with the current
SwiftUI implementation (`CampusHotWaterApp.swift`, `ServiceTile.swift`,
`QuickSetupView.swift`, `LaundryView.swift`, `NativeRootView.swift`). This is a
native Compose implementation; identical Apple font rasterization, SF Symbols,
system WebViews and system animation behavior are not claimed.

| Before | After | Why |
| --- | --- | --- |
| Card balance first and electricity currency second | Dorm kWh on the left, campus-card yuan on the right, both with separate timestamps | Match the iPhone's information hierarchy |
| Large icon and fee block on water detail | Small room line, status, horizontal fee row and recent settlement | Match the compact iPhone detail |
| Washer management above inline radio rows | Device card, separate program cards, pinned confirmation and collapsed saved-machine management | Keep the next action visible |
| Material navigation bar | Floating capsule with three accessible tabs | Match the current iPhone navigation shape |
| Default palette and 20dp cards | iOS grouped colors, 16dp cards and matched type sizes | Follow Native Clear source tokens |

The navigation capsule uses the upstream Apache-2.0
[Backdrop library 1.0.0](https://github.com/Kyant0/AndroidLiquidGlass/tree/1.0.0),
pinned to the stable Compose 1.9.4 / Kotlin 2.2 toolchain. The upstream 2.x branch
requires a newer toolchain and was reviewed but not introduced. This is an
independent implementation of blur/refraction, not Apple's proprietary renderer.
The full upstream license is included in the APK at
`assets/licenses/backdrop-LICENSE.txt`.

- Android 13+ (API 33+): a 10dp blur and restrained lens refraction.
- Android 12 / 12L (API 31–32): blur without RuntimeShader refraction.
- Older releases: a nearly opaque capsule with the same geometry and readable text.
- The user can disable glass in Devices. Low-RAM or power-save mode chooses the
  simple rendering path; capability is re-evaluated on Activity resume.
- Only one navigation-sized effect is used. Balances and financial information
  remain opaque. No extra background scanning or network polling is introduced.

### Verified locally

- JDK 21 clean build, main and instrumentation APK assembly passed.
- **20 unit tests passed**, including financial-intent persistence, timeout and
  account isolation, strict fee parsing, and API/power/memory effect gating.
- **17 screenshot scenarios passed** on an Android 16/API 36 emulator: 360/393/412dp,
  light/dark, 1.6x text, water, idle/running washer, setup, devices, recent orders,
  full glass, blur-only and simple rendering. Tab navigation was also exercised.
  Forced blur/simple modes on this emulator do not replace actual older-OS tests.
- Lint: zero errors; remaining warnings are retained in the local HTML report.
- APK v1/v2 signature verification passed; unsigned/Apple-profile installation
  claims are not made. The public app contains no personal profile or platform key.
- Detailed screenshots and build logs are kept locally and are not part of the
  public repository or release assets.

Physical Huawei nova 10/HarmonyOS 4.2, vivo X200 Pro/OriginOS 6 and Samsung
SM-S9280/Android 16 are still pending. No live login, SMS, authorization, settlement,
reservation, cancellation or payment was executed for this UI update. Android
launcher widgets, automatic private-platform provisioning and iOS Shortcuts parity
are not included in this package. Fresh water setup still needs the private
platform profile described above.


## Screenshot correction — alpha3

The approximate alpha2 preview was rejected by the user. The next pass used
installed-iPhone screenshots, kept tabs on detail pages, matched the compact
form layout and compared the screens at the same viewport. See
[the screenshot alignment record](android-ios-parity.md). The visual review was
approved on 2026-10-27, and the alpha3 APK was published as an earlier prerelease.
