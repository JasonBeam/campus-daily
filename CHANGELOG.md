# Changelog

版本记录采用 Keep a Changelog 格式。仓库只包含源码、教程和脱敏素材，不包含个人开发签名安装包。

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
[0.7.0]: https://github.com/JasonBeam/campus-daily/releases/tag/v0.7.0
