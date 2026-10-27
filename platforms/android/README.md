# 校日常 Android

This is the native Android implementation for the Huawei nova 10 (HarmonyOS 4.2)
vivo X200 Pro (OriginOS 6), and Samsung Galaxy S24 Ultra / SM-S9280
(Android 16) pilot devices.

## Compatibility target

- Minimum Android API: 23 (Android 6.0). This is the minimum supported by the
  bundled ML Kit QR scanner; the app does not require Google Play services for
  QR decoding.
- `compileSdk` 36, `targetSdk` 35. The target controls newer Android permission
  and UI behavior; it does not prevent installation on supported older Android
  versions.
- BLE scanning and camera access are requested only when the user starts the
  relevant feature. Android 6–11 use the legacy Bluetooth/location permission
  path; Android 12 and later use Nearby devices permissions.
- The app keeps BLE scanning in the foreground and does not request background
  location. `BLUETOOTH_SCAN` intentionally omits `neverForLocation`: Android
  documents that flag can filter some BLE beacons, and this app must discover
  the school water controller by its advertisement name.

## Signing and installation

Android requires every installable APK to be digitally signed. This is an APK
signing key held by the publisher, not an Apple provisioning profile. Testers do
not need their own signing certificate or a paid developer account. Updates
must keep using the same publisher key; never upload that private key to GitHub.

Installing a sideloaded APK can still show an Android or vendor security prompt.
On HarmonyOS 4.2, Huawei documents that the user may need to turn off Pure mode's
Enhanced protection, then confirm the external APK install. OriginOS may also
show its own unknown-source or risk warning. These prompts are separate from
signing the APK and cannot be eliminated by lowering `minSdk`.

For a small test group, Android's free Limited distribution account can register
an app for up to 20 explicitly approved devices. It is optional for the current
direct-download pilot; direct sideloading is not currently subject to the
September 2026 regional enforcement phase. Google says the broader rollout is
planned for 2027, so the distribution rules should be rechecked before a wider
release.

## Current feature scope

Version 0.2.0-alpha3 includes the Native Clear interface, three tabs, light/dark
themes, school WebView login, card/electricity balance and official recharge,
room/controller selection and BLE identity verification, water authorization and
settlement, U净 login, saved washers, reservation, Alipay SDK/checkout handoff,
server order refresh/countdown and unpaid cancellation. First-time water setup
still needs a private platform profile import. Android launcher widgets are not
included. Physical-device acceptance on all three pilot phones remains required.

See [migration design, sources and acceptance notes](../../docs/android-migration.md).
Build from the repository root with `bash tools/build-android.sh` using JDK 21.

Do not put personal tokens, water-platform secrets, device identifiers, signing
keys, or real student data in the repository or an APK source file.


The alpha3 UI aligns the home information order, water detail, program cards and
setup with the current iPhone implementation. Backdrop 1.0.0 provides optional
navigation glass: refraction on API 33+, blur-only on 31–32, simple capsule on
older/low-RAM/power-save devices. Devices includes a glass toggle. System fonts,
icons and official web/payment screens remain platform-specific. Local acceptance
is documented in `docs/android-migration.md`; it is not physical-device sign-off.
