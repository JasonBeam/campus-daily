# Android / iPhone screenshot alignment

The visual baseline is the installed iPhone 16 Pro Max app captured on
2026-10-27. The older `docs/screenshots` promotional set is not used as the
current baseline. Six reference pages and their accessibility coordinates are
kept only in ignored local artifacts.

| Before | After | Why |
| --- | --- | --- |
| Approximate source-based preview at a different phone width | Side-by-side real screenshots at the same 440 x 956 viewport | Compare actual layout rather than separate scaled images |
| Tab bar hidden on details | Capsule retained on water, laundry and setup | Match the installed app's navigation |
| Wide Material-style navigation and icon family | Compact 280dp capsule and original geometric outlines | Match the reference proportions without redistributing Apple font assets |
| Centered financial-action text | Leading action, trailing amount or arrow | Match the reference button layout |
| Icon-heavy Devices page | Compact grouped form, small inline title and advanced disclosure | Match the installed Settings view |
| Extra CJK fallback line spacing accumulated down the page | Explicit line grid with multiline measurement and font-scale support | Reduce repeated vertical offsets |
| Machine management permanently above program choices | Separate saved-machine setup, program detail stays focused | Preserve adding and switching multiple washers |

## Local-only evidence

`artifacts/android/ios-match/preview.html` displays the original iPhone screenshots
and actual Android Compose renders. Android uses fixture accounts, balances and
orders, inert actions and normalized preview safe areas. It does not fake an iOS
status bar. Production uses the Android system's real safe areas. The preview
activity is debug-only; it never constructs a network client or repository.

- `reference-manifest.json`: capture provenance and viewport.
- `reference-geometry.json`: measured iPhone point coordinates.
- `android/*440dp*.json`: actual Android text bounds from the layout tests.
- `verification.json`, `build.log`, `layout-test.log`: package and local checks.

Water, electricity, laundry, recharge and transaction state code is unchanged by
this alignment. The public APK still needs each tester's own configuration;
private platform data is not embedded. No real SMS, water start, settlement,
reservation, payment or cancellation is performed by the layout tests.

The user approved the side-by-side visual review on 2026-10-27. Android
system permissions, official login/payment pages, system status bars, font
rasterization and the independent glass renderer are not claimed to be Apple's
implementation. The approved alpha3 package is published as a GitHub prerelease. Private reference screenshots are not published.

## Verification for alpha3

- Version code 5 / 0.2.0-alpha3-debug, APK v1/v2 signatures verified.
- 20 unit tests passed. Lint completed with zero errors.
- 23 screenshot scenarios plus navigation switching passed on the API 36 emulator.
- Six same-viewport pairs were visually reviewed, including completed setup and
  completed laundry. Small-width, dark and large-font variants were also checked.
- The reference iPhone session was stopped after capture; no phone connection is
  needed for ongoing Android development from these local files.
- Physical Android login, BLE and payment acceptance remains pending.
