import SwiftUI
import UserNotifications
import Core

#if DEBUG
/// The campusdaily://demo/... URLs in 清爽, on the same synthetic data as 暖橙's
/// (`HomeView+Demo`), so screenshots can be taken in either theme.
extension ClearRootView {
    /// Also called from inside the sheets and covers: while one is up, the URL is delivered to
    /// its hierarchy instead of the root.
    func handleDemo(_ url: URL) {
        if let kind = notifyDemo(url) { Task { await reminders.demoNotify(kind) }; return }
        // campusdaily://demo/theme/<warm|clear>: what 主题 would pick.
        if url.host == "demo", url.pathComponents.dropFirst().first == "theme",
           let theme = AppTheme(rawValue:url.lastPathComponent) { themeStore.select(theme); return }
        if let page = WidgetPreview.handle(url) { activityPreview = nil; widgetPreview = page; return }
        widgetPreview = nil
        if let kind = LaundryActivityPreview.handle(url) { activityPreview = kind; return }
        activityPreview = nil
        if LaundryActivityController.handleDemo(url) { return }
        let name = url.lastPathComponent
        let normal = HomeDemo.normal.content().0
        if url.host == "demo", name == "login-loading" {
            navigator.setup = nil; popAll()
            navigator.demo = normal
            Task { try? await Task.sleep(for:.milliseconds(400)); loginDemo = true }
            return
        }
        if let onboard = OnboardingDemo.handle(url) {
            // 清爽 has the checklist instead of the paged guide: the step's row pushed.
            popAll()
            navigator.setup = ClearNavigator.SetupRequest(start:setupRow(onboard.0), preview:onboard.1)
            return
        }
        if let laundryPage = LaundryDemo.handle(url) {
            navigator.setup = nil
            navigator.demo = normal
            navigator.laundryDemo = laundryPage
            navigator.panel = laundryPage.panel
            freshPush(.laundry)
            return
        }
        if let records = RecordsDemo.handle(url) {
            navigator.setup = nil; navigator.panel = nil; navigator.laundryDemo = nil
            navigator.demo = normal
            navigator.recordsDemo = records
            recordsDemoRun += 1
            popAll()
            navigator.tab = .records
            return
        }
        if url.host == "demo", name == "recharge-blocked" {
            navigator.setup = nil
            navigator.demo = normal
            navigator.rechargeBlockedDemo = true
            freshPush(.card)
            return
        }
        if url.host == "demo", name.hasPrefix("account-switched") || name.hasPrefix("account-unconfirmed") {
            navigator.setup = nil; popAll()
            navigator.demo = normal
            campus.switchNotice = AccountSwitchNotice(previousPersonUnconfirmed:name.hasPrefix("account-unconfirmed"),
                                                      hotWaterCleared:name.hasSuffix("-water"))
            return
        }
        if url.host == "demo", ["meter-stopped", "meter-stopped-finding", "meter-stopped-slow", "meter-ask", "meter-ask-mixed", "meter-unfinished"].contains(name) {
            navigator.setup = nil; navigator.panel = nil; navigator.laundryDemo = nil
            navigator.demo = HomeDemo.noMeter.content().0
            campus.demoMeterStop(running:name.hasSuffix("finding"), slow:name.hasSuffix("slow"),
                                 ask:name == "meter-ask", unfinished:name == "meter-unfinished", mixed:name == "meter-ask-mixed")
            freshPush(.powerSetup)
            return
        }
        if url.host == "demo", name == "permission" {
            navigator.setup = nil; popAll()
            navigator.demo = normal
            reminders.prompt = .app
            return
        }
        if url.host == "demo", name == "permission-home" {
            navigator.setup = nil; navigator.panel = nil; navigator.laundryDemo = nil; popAll()
            navigator.demo = normal
            reminders.demoHomeRead()
            return
        }
        if url.host == "demo", name == "sh-from-settings" {
            // 设置 up, then a start: 日常 selected and the page pushed.
            navigator.setup = nil; navigator.panel = nil; navigator.laundryDemo = nil; popAll()
            navigator.demo = normal
            navigator.tab = .settings
            Task {
                try? await Task.sleep(for:.seconds(1.5))
                shower.showDemoPage(HomeView.ShowerPageDemo.record("sh-connect"))
            }
            return
        }
        if url.host == "demo", name == "sh-under-onboarding" {
            // The checklist up, then a shower ended from the lock screen: it closes, the result shows.
            navigator.panel = nil; navigator.laundryDemo = nil; popAll()
            navigator.demo = normal
            navigator.openSetup()
            Task {
                try? await Task.sleep(for:.seconds(1.5))
                shower.showDemoPage(HomeView.ShowerPageDemo.record("sh-done"))
            }
            return
        }
        if url.host == "demo", let record = HomeView.ShowerPageDemo.record(name) {
            // The shower page on a synthetic record (nothing connects).
            navigator.setup = nil; navigator.panel = nil; navigator.laundryDemo = nil
            popAll()
            navigator.demo = normal
            if record.phase == .running, let start = record.startedAt { navigator.demo?.shower = .showering(start) }
            if record.stateReviewRequired { navigator.demo?.shower = .needsCheck }
            shower.showDemoPage(record)
            if name == "sh-endfail" { shower.page.endFailed = .noConnection }
            switch name {
            case "sh-check-rechecking", "sh-detail-check-rechecking": shower.page.rechecking = true
            case "sh-check-stopped": shower.page.recheckResult = .stopped
            case "sh-check-nocon": shower.page.recheckResult = .noConnection
            case "sh-check-bt": shower.page.recheckResult = .bluetoothOff
            case "sh-check-busy": shower.page.recheckResult = .busy
            case "sh-check-failed": shower.page.recheckResult = .failed
            case "sh-check-unavailable": shower.page.recheckResult = .unavailable
            default: break
            }
            if name.hasPrefix("sh-detail") {
                // The same page, not brought up by the model.
                shower.page.presented = false
                navigator.homePath = [.shower]
            } else {
                followShowerPage(shower.page.presented)
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
        reminders.demoStatus = settingsDemos[name]
        guard let result = HomeDemo.handle(url) else { return }
        navigator.setup = nil; navigator.laundryDemo = nil; navigator.recordsDemo = nil
        popAll()
        withAnimation(Theme.spring) {
            navigator.demo = result?.0
            navigator.panel = result?.1
        }
        if settingsDemos[name] != nil {
            navigator.tab = .settings
            if result?.0.themePageShown == true { navigator.settingsPath = [.theme] }
        }
    }

    /// The checklist row for a step of 暖橙's guide.
    func setupRow(_ step: OnboardingView.Step) -> ClearSetupRow? {
        switch step {
        case .login: .account
        case .washer: .laundry
        case .dorm: .dorm
        case .water: .controller
        case .done: nil
        }
    }

    /// A page pushed anew on 日常, so its @State starts from the demo.
    func freshPush(_ route: ClearRoute) {
        popAll()
        Task { try? await Task.sleep(for:.milliseconds(350)); reveal([route]) }
    }

    func notifyDemo(_ url: URL) -> String? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "notify" else { return nil }
        return parts.count > 1 ? parts[1] : "laundry"
    }
}
#endif
