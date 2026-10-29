# Changelog

版本记录采用 Keep a Changelog 格式。源码仓库不保存个人签名证书或个人配置；测试安装包通过 GitHub Release 单独分发。

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
