# Repository rules

The rules for working in this repo, for people and AI agents alike. The full design is in
`docs/architecture.md`.

## Layout

- `App/Application/`: app entry and `AppEnvironment` (creates and wires the services). No feature logic.
- `App/Interface/<Feature>/`: views and view models for Home, CampusCard, Shower, Laundry, Onboarding, Settings. A type goes in `Interface/Common/` only when two or more features use it. These are 暖橙's pages; 清爽's own page tree is in `Interface/Clear/`, and `CampusRootView` picks one by theme.
- `App/Services/`: platform side effects (Bluetooth, school web login, background refresh, Alipay, Live Activities, App Intents, reminders).
- `Shared/`: code compiled into both App and Widget (widget views, Live Activity views, and in `Theme/` only the formatting, shapes and colours the widget and Live Activities need, such as the 清爽 palette; the app's tokens and fonts stay in `App/Interface/Common/`).
- `Packages/Core/`: all logic that can run without UI. It must not import SwiftUI, UIKit, WidgetKit, ActivityKit or CoreBluetooth. `Storage/` holds only generic Keychain and UserDefaults access; each feature keeps its own vault protocol and store in its folder.
- Xcode uses synchronized folders, so adding a file needs no project edit. Identity and versions live in `Configuration/*.xcconfig`. Local signing goes in the untracked `Configuration/Developer.xcconfig`.

## Dependencies

`App → Shared → Core`, `Widget → Shared → Core`. Inside Core, Campus, Shower and Laundry depend only on Networking, Storage and Common, never on each other. Snapshot reads Campus and Storage. Theme reads the Shower and Laundry states and Storage. Only Networking makes network requests. The widget reads the snapshot. It never drives the shower or laundry state machines.

## Code

- State shared across processes (app and widget) changes only through an atomic compare-and-modify (one locked read-compare-write, like the refresh lease file's `flock`) or while holding that lease; never by a read and a separate write alone.

- iOS 17. Core, App and Widget build in Swift 6 language mode. Today's screen models are `ObservableObject` (some with `.shared` singletons, see docs/architecture.md); new code passes dependencies through initializers instead of adding singletons. Time, network and Bluetooth are injectable.
- One main type per file, named after the type. Split files over 400 lines by responsibility (`HomeView+Rows.swift`).
- Feature names are Campus, Shower, Laundry and Snapshot everywhere. Do not use Water, HotWater or DailyXxx in new names.
- Comment only what the code cannot say, for example a field order that the platform signs.
- Logs record event names only. Never log student ids, device ids, tokens or BLE payloads.
- Problems and errors use the notice colour (`Theme.notice`, `NativeTheme.notice`). Red is only for running out: a low balance or low electricity.

## Do not change casually

Hot-water signing, BLE commands, and how school and U净 responses are parsed must match what the real services expect. Any change to them goes in its own commit with the reason. Money paths (opening water, settling, laundry payment) save state before each step. When the outcome is unknown they stop for the user and never retry automatically.

## Privacy

The repo is public. Real student ids, phone numbers, rooms, device ids, keys and raw captures never go in it. Fixtures in `Packages/Core/Tests/Fixtures` are captured replies with every personal value replaced by a fake one, plus synthetic replies for calls that were never captured (redaction rules in docs/architecture.md). `mise scan` checks the staged files. It needs two lists kept outside the repo: your private values (`LEAKCHECK_FILE`, default `private/capture/secrets/leakcheck.txt`) and marker patterns (`MARKER_PATTERNS`, with optional `MARKER_ALLOW` of `path:line` exceptions); a missing list fails.

Settings › 反馈问题 sends only the typed text, the screenshots the user picks (re-encoded as JPEG, so no location or other photo metadata), app version and build, device model, OS version and locale. Never add the account, student id, balances or logs to it; docs/privacy.md says the same to users. Its endpoint and key live in the untracked `private/distribution/Feedback.xcconfig`, which `Configuration/Base.xcconfig` includes if present; without it the build has no 反馈问题 row. Never commit that file.

## Before committing

Run `mise run check`: Debug and Release builds, all tests, the App.xctestplan on a simulator, and `mise scan`. Deleting a test needs a stated reason in the PR. To build or test on another machine, set `BUILD_CMD` / `TEST_CMD` / `TEST_APP_CMD`. Each commit does one thing, with its tests in the same commit; keep pure moves separate from logic changes. Commit titles follow Conventional Commits, `type(scope): lowercase imperative` in at most 72 characters (`fix(settings): say when a screenshot can't be added`). No merge commits. Docs are this file, `README.md`, `docs/architecture.md`, `docs/privacy.md` and `CHANGELOG.md`. Do not add process notes. Screenshots and release images live in `docs/media/`, one folder per version: new ones go in a new version folder, old ones stay as they are.
