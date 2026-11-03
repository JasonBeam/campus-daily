import SwiftUI
import UserNotifications
import Core

#if DEBUG
extension HomeView {
    /// Also called from inside the onboarding cover: while a full-screen cover is up,
    /// the URL is delivered to the cover's hierarchy instead of the home view.
    func handleDemo(_ url: URL) {
            if let kind = notifyDemo(url) { Task { await reminders.demoNotify(kind) }; return }
            // campusdaily://demo/theme/<warm|clear>: what 主题 would pick, keeping the screen shown.
            if url.host == "demo", url.pathComponents.dropFirst().first == "theme",
               let theme = AppTheme(rawValue:url.lastPathComponent) { themeStore.select(theme); return }
            if let page = WidgetPreview.handle(url) { activityPreview = nil; widgetPreview = page; return }
            widgetPreview = nil
            if let kind = LaundryActivityPreview.handle(url) { activityPreview = kind; return }
            activityPreview = nil
            if LaundryActivityController.handleDemo(url) { return }
            if url.host == "demo", url.lastPathComponent == "login-loading" {
                onboarding = nil; settings = false; path = []
                demo = HomeDemo.normal.content().0
                Task { try? await Task.sleep(for:.milliseconds(400)); loginDemo = true }
                return
            }
            if let onboard = OnboardingDemo.handle(url) {
                settings = false; path = []
                onboarding = OnboardingRequest(step:onboard.0, preview:onboard.1)
                return
            }
            if let laundryPage = LaundryDemo.handle(url) {
                onboarding = nil
                demo = HomeDemo.normal.content().0
                laundryDemo = laundryPage; washerDemo = nil
                panel = laundryPage.panel
                // Fresh push so the page's @State starts from this demo.
                freshPush(.laundry)
                return
            }
            if let washer = WasherSetupDemo.handle(url) {
                // 常用洗衣机 over the home demo; a fresh push so the page starts from this demo.
                onboarding = nil; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                washerDemo = washer
                freshPush(.washerSetup)
                return
            }
            if let records = RecordsDemo.handle(url) {
                // 校园卡记录 over the home demo; a fresh push so the page starts from this demo.
                onboarding = nil; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                recordsDemo = records; washerDemo = nil
                freshPush(.records)
                return
            }
            if url.host == "demo", url.lastPathComponent == "recharge-blocked" {
                onboarding = nil
                demo = HomeDemo.normal.content().0
                rechargeBlockedDemo = true
                freshPush(.card)
                return
            }
            if url.host == "demo", url.lastPathComponent.hasPrefix("account-switched") || url.lastPathComponent.hasPrefix("account-unconfirmed") {
                // Account-switch alert over the home demo (「account-unconfirmed」: the login couldn't
                // tell the previous person); 「-water」 adds the hot-water line and button.
                onboarding = nil; settings = false; path = []
                demo = HomeDemo.normal.content().0
                campus.switchNotice = AccountSwitchNotice(previousPersonUnconfirmed:url.lastPathComponent.hasPrefix("account-unconfirmed"),
                                                          hotWaterCleared:url.lastPathComponent.hasSuffix("-water"))
                return
            }
            if url.host == "demo", ["meter-stopped", "meter-stopped-finding", "meter-stopped-slow", "meter-ask", "meter-ask-mixed", "meter-unfinished"].contains(url.lastPathComponent) {
                // The meter page where the lookup stopped (synthetic): as is / looking again / slow school /
                // two apartments with the dorm's room (or one, the other halted) / one of them not read.
                onboarding = nil; panel = nil; laundryDemo = nil
                demo = HomeDemo.noMeter.content().0
                campus.demoMeterStop(running:url.lastPathComponent.hasSuffix("finding"), slow:url.lastPathComponent.hasSuffix("slow"),
                                     ask:url.lastPathComponent == "meter-ask", unfinished:url.lastPathComponent == "meter-unfinished",
                                     mixed:url.lastPathComponent == "meter-ask-mixed")
                freshPush(.powerSetup)
                return
            }
            if url.host == "demo", url.lastPathComponent == "permission" {
                // Pre-permission sheet over the home demo, whatever the real authorization is.
                onboarding = nil; settings = false; path = []
                demo = HomeDemo.normal.content().0
                reminders.prompt = .app
                return
            }
            if url.host == "demo", url.lastPathComponent == "permission-home" {
                // Home demo, then the first-home-read trigger: the sheet appears once home is clear.
                onboarding = nil; settings = false; path = []; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                reminders.demoHomeRead()
                return
            }
            if url.host == "demo", url.lastPathComponent == "sh-from-settings" {
                // Settings up, then a start: the sheet closes and the page comes up.
                onboarding = nil; path = []; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                settings = true
                Task {
                    try? await Task.sleep(for:.seconds(1.5))
                    shower.showDemoPage(ShowerPageDemo.record("sh-connect"))
                }
                return
            }
            if url.host == "demo", url.lastPathComponent == "sh-under-onboarding" {
                // The first-run guide up, then a shower ended from the lock screen: the guide
                // closes and the result comes up.
                path = []; panel = nil; laundryDemo = nil; settings = false
                demo = HomeDemo.normal.content().0
                onboarding = OnboardingRequest(step:.login, preview:OnboardingView.Preview(dorm:"3 栋 108"))
                Task {
                    try? await Task.sleep(for:.seconds(1.5))
                    shower.showDemoPage(ShowerPageDemo.record("sh-done"))
                }
                return
            }
            if url.host == "demo", let record = ShowerPageDemo.record(url.lastPathComponent) {
                // The shower page over the home demo, on a synthetic record (nothing connects).
                onboarding = nil; settings = false; path = []; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                // Collapsed while water runs, home shows the showering button, as it would live.
                if record.phase == .running, let start = record.startedAt { demo?.shower = .showering(start) }
                if record.stateReviewRequired { demo?.shower = .needsCheck }
                shower.showDemoPage(record)
                if url.lastPathComponent == "sh-endfail" { shower.page.endFailed = .noConnection }
                switch url.lastPathComponent {
                case "sh-check-rechecking": shower.page.rechecking = true
                case "sh-check-stopped": shower.page.recheckResult = .stopped
                case "sh-check-nocon": shower.page.recheckResult = .noConnection
                case "sh-check-bt": shower.page.recheckResult = .bluetoothOff
                case "sh-check-busy": shower.page.recheckResult = .busy
                case "sh-check-failed": shower.page.recheckResult = .failed
                case "sh-check-unavailable": shower.page.recheckResult = .unavailable
                case "sh-detail-check-rechecking": shower.page.rechecking = true
                default: break
                }
                if url.lastPathComponent.hasPrefix("sh-detail") {
                    // The 热水洗澡 screen over home, the page down.
                    shower.page.presented = false
                    path = [.shower]
                }
                return
            }
            let settingsDemos: [String:UNAuthorizationStatus] = ["settings":.authorized, "settings-notif-off":.denied,
                                                                  "settings-ask":.notDetermined, "settings-password-on":.authorized,
                                                                  "settings-paused":.authorized, "settings-paused-noanswer":.authorized,
                                                                  "settings-web-login":.authorized,
                                                                  "settings-reset-shower":.authorized, "settings-reset-unsure":.authorized,
                                                                  "settings-laundry-off":.authorized, "settings-laundry-locked":.authorized,
                                                                  "settings-theme":.authorized, "settings-theme-shower":.authorized,
                                                                  "settings-theme-laundry":.authorized, "settings-theme-both":.authorized]
            reminders.demoStatus = settingsDemos[url.lastPathComponent]
            guard let result = HomeDemo.handle(url) else { return }
            onboarding = nil; settings = false; path = []; laundryDemo = nil; recordsDemo = nil; washerDemo = nil
            withAnimation(Theme.spring) {
                demo = result?.0
                panel = result?.1
            }
            if settingsDemos[url.lastPathComponent] != nil {
                // Let any open sheet dismiss first, otherwise the reopen is coalesced away.
                Task { try? await Task.sleep(for:.milliseconds(500)); settings = true }
            }
    }
    /// campusdaily://demo/sh-<face>: connect, run, settle, done, nocon, denied, busy, unsure, check,
    /// endfail (back on the timer after an end that didn't go through), check-rechecking,
    /// check-stopped, check-nocon, check-bt, check-busy, check-failed, check-unavailable
    /// (再查一次水控 running, then what it found or why it could not look); detail-check,
    /// detail-check-rechecking (the same record on the 热水洗澡 screen).
    enum ShowerPageDemo {
        static func record(_ name: String, now: Date = Date()) -> ShowerState? {
            let start = now.addingTimeInterval(-(8 * 60 + 42))
            func failed(_ reason: ShowerFailureReason, review: Bool) -> ShowerState {
                // Only a failure after the water carries the timer's start.
                ShowerState(phase:.failed, startedAt:reason.isBeforeWater ? nil : start,
                            failure:ShowerFailure(reason:reason, needsReview:review))
            }
            switch name {
            case "sh-connect": return ShowerState(phase:.authorizing)
            case "sh-run", "sh-endfail": return ShowerState(phase:.running, startedAt:start)
            case "sh-check", "sh-check-rechecking", "sh-check-stopped", "sh-check-nocon",
                 "sh-check-bt", "sh-check-busy", "sh-check-failed", "sh-check-unavailable",
                 "sh-detail-check", "sh-detail-check-rechecking": return ShowerState(phase:.running, startedAt:start, stateReviewRequired:true, notice:.notActive)
            case "sh-settle": return ShowerState(phase:.settling, startedAt:start)
            case "sh-done":
                return ShowerState(phase:.done, startedAt:now.addingTimeInterval(-11 * 60),
                                   receipt:ShowerReceipt(amount:Money(fen:132)), endedAt:now)
            case "sh-nocon": return failed(.deviceUnavailable, review:false)
            case "sh-denied": return failed(.authorizeRefused, review:false)
            case "sh-busy": return failed(.deviceBusy, review:false)
            case "sh-unsure": return failed(.settleUncertain, review:true)
            default: return nil
            }
        }
    }

    /// campusdaily://demo/notify/<kind>
    /// A page pushed anew, so its @State starts from the demo: after the settings sheet has gone
    /// when it is up (`open(_:)`), otherwise a moment after home's pages are popped.
    func freshPush(_ route: HomeRoute) {
        if settings { open([route]); return }
        path = []; pathAfterSettings = nil
        Task { try? await Task.sleep(for:.milliseconds(350)); path = [route] }
    }

    func notifyDemo(_ url: URL) -> String? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "notify" else { return nil }
        return parts.count > 1 ? parts[1] : "laundry"
    }

    func demoTap(_ kind: HomeShowerButton.Kind) {
        switch kind {
        case .start:
            startTick += 1
            withAnimation(Theme.spring) { demo?.shower = .showering(Date()) }
        case .showering where shower.page.record.phase == .running:
            // Collapsed from a demo page: open it again, as the live button does.
            shower.pageEvent(.reopen)
        case .showering(let start, _):
            withAnimation(Theme.spring) { demo?.shower = .settling(start) }
            Task {
                try? await Task.sleep(for:.seconds(1.5))
                let minutes = max(1, Int((Date().timeIntervalSince(start) / 60).rounded()))
                withAnimation(Theme.spring) {
                    demo?.shower = .idle
                    demo?.lastShowerMinutes = minutes; demo?.lastShowerCost = Decimal(string:"1.32")
                    demo?.appActivities.insert(AppActivity(id:"demo-\(Date().timeIntervalSince1970)", kind:.shower(minutes:minutes),
                                                           date:Date(), amount:Money(fen:132)), at:0)
                }
                successTick += 1
                if let record = ShowerPageDemo.record("sh-done") { shower.showDemoPage(record) }
            }
        case .signIn: openOnboarding()
        case .review, .settling: path.append(.shower)
        case .check: shower.pageEvent(.reopen)
        case .starting: break
        }
    }
}
#endif
