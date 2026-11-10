#if DEBUG
import SwiftUI
import Core

// MARK: - DEBUG demo data (campusdaily://demo/<state>); never compiled into Release.

enum HomeDemo: String, CaseIterable {
    case normal, low, empty, shower, off, settings
    /// 学校洗衣机 off: home without laundry / settings with the switch off / switch locked by an order.
    case laundryOff = "home-laundry-off"
    case settingsLaundryOff = "settings-laundry-off"
    case settingsLaundryLocked = "settings-laundry-locked"
    case settingsOff = "settings-notif-off"
    case settingsAsk = "settings-ask"
    /// Settings › 学校账号 with the password saved (synthetic account and password).
    case settingsPassword = "settings-password-on"
    /// Settings › 学校账号 with automatic sign-in paused: password refused / login got no answer.
    case settingsPaused = "settings-paused"
    case settingsPausedNoAnswer = "settings-paused-noanswer"
    /// Signed in on the web page (no account known): typing another account shows the mismatch alert.
    case settingsWebLogin = "settings-web-login"
    /// Settings › 高级 › 重置校日常 locked: showering / a settlement to check.
    case settingsResetShower = "settings-reset-shower"
    /// 重置校日常 open over a shower that is over (kept for the school): it doesn't lock reset.
    case settingsResetKept = "settings-reset-kept"
    case settingsResetLaundry = "settings-reset-laundry"
    /// Settings › 外观 › 主题: open / greyed out by a shower, a laundry order, both.
    case settingsTheme = "settings-theme"
    case settingsThemeShower = "settings-theme-shower"
    case settingsThemeLaundry = "settings-theme-laundry"
    case settingsThemeBoth = "settings-theme-both"
    case unconfirmedRow = "unconfirmed-row"
    /// Showering while the authorization write is unconfirmed (stage .authorizationWritePending).
    case showerUnconfirmed = "shower-unconfirmed"
    case laundryRun = "home-laundry-run"
    case laundryCheck = "home-laundry-check"
    /// Hot-water row when the build has no bundled platform profile (OnboardingError.platform).
    case noPlatform = "no-platform"
    /// Hot-water row when the service says this school isn't open (transactions_not_enabled).
    case notOpen = "not-open"
    /// The update line while reading, after a failed read, and with the card records unread.
    case updating = "home-updating"
    case failed = "home-fail"
    case noRecords = "home-notx"
    /// The update line when reads keep ending without storing their numbers.
    case notSaving = "home-notsaving"
    /// 电量 with no meter bound: not found (opens the meter page) / being looked for.
    case noMeter = "home-nometer"
    case findingMeter = "home-findingmeter"

    static func handle(_ url: URL) -> (HomeData, SettlementResult?)?? {
        guard url.scheme == "campusdaily", url.host == "demo" else { return nil }
        let name = url.pathComponents.dropFirst().first ?? "normal"
        if name == "exit" { return .some(nil) }
        guard let demo = HomeDemo(rawValue:name) else { return nil }
        return .some(demo.content())
    }

    func content(now: Date = Date()) -> (HomeData, SettlementResult?) {
        let calendar = Calendar.current
        var data = HomeData.sample(now:now)
        let read = now.addingTimeInterval(-25 * 60)
        switch self {
        case .normal, .settings, .settingsOff, .settingsAsk: return (data, nil)
        case .updating:
            data.refreshing = true
            return (data, nil)
        case .failed:
            data.snapshot.card.fail(.offline, at:now)
            data.snapshot.power.fail(.offline, at:now)
            data.snapshot.activity.fail(.offline, at:now)
            return (data, nil)
        case .noRecords:
            data.snapshot.activity = Tile()
            return (data, nil)
        case .notSaving:
            data.notSaving = true
            return (data, nil)
        case .noMeter:
            data.powerBound = false
            data.meterLocation = nil
            return (data, nil)
        case .findingMeter:
            data.powerBound = false; data.findingMeter = true
            data.meterLocation = nil
            return (data, nil)
        case .settingsResetShower:
            data.shower = .showering(now.addingTimeInterval(-(8 * 60 + 42)))
            data.resetLock = .showering
            return (data, nil)
        case .settingsResetKept:
            data.shower = .stopped
            data.resetLock = AppReset.lock(shower:SampleData.showerRecord("sh-stopped", now:now))
            return (data, nil)
        case .settingsResetLaundry:
            data.resetLock = .laundry
            return (data, nil)
        case .settingsTheme:
            data.themePageShown = true
            return (data, nil)
        case .settingsThemeShower:
            data.themePageShown = true; data.themeLock = .shower
            data.shower = .showering(now.addingTimeInterval(-(8 * 60 + 42)))
            return (data, nil)
        case .settingsThemeLaundry:
            data.themePageShown = true; data.themeLock = .laundry
            data.laundry = .running(program:"标准洗", end:now.addingTimeInterval(18 * 60 - 30))
            return (data, nil)
        case .settingsThemeBoth:
            data.themePageShown = true; data.themeLock = .showerAndLaundry
            data.shower = .showering(now.addingTimeInterval(-(8 * 60 + 42)))
            data.laundry = .running(program:"标准洗", end:now.addingTimeInterval(18 * 60 - 30))
            return (data, nil)
        case .settingsPassword:
            data.schoolAccount = SchoolAccount(account:"99100991", password:"demo-password")
            return (data, nil)
        case .settingsPaused:
            data.schoolAccount = SchoolAccount(account:"99100991", password:"demo-password", paused:true)
            return (data, nil)
        case .settingsWebLogin:
            data.schoolAccount = nil
            return (data, nil)
        case .settingsPausedNoAnswer:
            data.schoolAccount = SchoolAccount(account:"99100991", password:"demo-password", unansweredAt:now)
            return (data, nil)
        case .laundryOff, .settingsLaundryOff:
            data.laundryEnabled = false
            return (data, nil)
        case .settingsLaundryLocked:
            data.laundryLocked = true
            data.laundry = .running(program:"标准洗", end:now.addingTimeInterval(18 * 60 - 30))
            return (data, nil)
        case .laundryRun:
            data.laundry = .running(program:"标准洗", end:now.addingTimeInterval(18 * 60 - 30))
            data.laundryOrder = LaundryOrderStatus("40").label
            return (data, nil)
        case .laundryCheck:
            data.laundry = .unresolved
            data.laundryOrder = "订单结果待核对"
            return (data, nil)
        case .unconfirmedRow:
            data.shower = .stopped
            return (data, nil)
        case .low:
            // Runs out tomorrow evening (只够到明晚); the balance is under the default line too.
            let target = calendar.date(bySettingHour:21, minute:0, second:0, of:calendar.date(byAdding:.day, value:1, to:now)!)!
            let days = target.timeIntervalSince(read) / 86400
            data.snapshot = Self.snapshot(now:now, read:read, kwh:"4.8", dailyKWh:String(format:"%.3f", 4.8 / days), balance:"12.40")
            data.laundry = .running(program:"标准洗", end:now.addingTimeInterval(18 * 60 - 30))
            return (data, nil)
        case .empty:
            var empty = HomeData(); empty.signedIn = false  // Signed out the profile, and so the dorm, is gone.
            empty.laundryBound = true; empty.laundryMachine = "3"; empty.laundry = .idle
            return (empty, nil)
        case .shower:
            data.shower = .showering(now.addingTimeInterval(-(8 * 60 + 42)))
            return (data, nil)
        case .showerUnconfirmed:
            data.shower = .showering(now.addingTimeInterval(-(8 * 60 + 42)))
            data.showerUnconfirmed = true
            return (data, nil)
        case .off:
            data.shower = .unconfigured
            return (data, nil)
        case .noPlatform:
            // Live path: ShowerModel.platformMissing (direct dorm saved, no bundled platform profile).
            data.shower = .unavailable(ShowerModel.platformMissingText)
            return (data, nil)
        case .notOpen:
            data.shower = .unavailable("本校暂未开放")
            return (data, nil)
        }
    }

    static var showerAgo: TimeInterval { SampleData.showerAgo }
    static var laundryAgo: TimeInterval { SampleData.laundryAgo }

    static func snapshot(now: Date, read: Date, kwh: String, dailyKWh: String, balance: String = "86.50") -> HomeSnapshot {
        SampleData.homeSnapshot(now:now, read:read, kwh:kwh, dailyKWh:dailyKWh, balance:balance)
    }
}
#endif
