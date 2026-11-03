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
    case settingsResetUnsure = "settings-reset-unsure"
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
        var data = HomeData()
        data.dorm = "3 栋 108"
        data.dormLocation = "北校区 · 东苑公寓 · 3 栋 · 108"
        data.meterLocation = "北校区 · 东苑公寓 · 3 栋 · 108"
        data.schoolAccount = SchoolAccount(account:"99100991")
        let read = now.addingTimeInterval(-25 * 60)
        data.snapshot = Self.snapshot(now:now, read:read, kwh:"42.6", dailyKWh:"4.6")
        data.lastShowerMinutes = 11; data.lastShowerCost = Decimal(string:"1.32")
        data.laundryBound = true; data.laundryMachine = "3"; data.laundry = .idle
        data.appActivities = [
            AppActivity(id:"demo-shower", kind:.shower(minutes:11), date:now.addingTimeInterval(-Self.showerAgo), amount:Money(fen:132)),
            AppActivity(id:"demo-laundry", kind:.laundry(program:"标准洗"), date:now.addingTimeInterval(-Self.laundryAgo),
                        amount:Money(fen:400), detail:"3 号机"),
        ]
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
        case .settingsResetUnsure:
            data.shower = .unresolved(.settlement)
            data.resetLock = .unsettled
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
            return (data, nil)
        case .laundryCheck:
            data.laundry = .unresolved
            return (data, nil)
        case .unconfirmedRow:
            data.shower = .unresolved(.settlement)
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

    /// The demo shower ended this long before now; its card record follows a minute later, so
    /// 最近 shows the shower once.
    static let showerAgo: TimeInterval = 20 * 3600
    /// The demo laundry order was paid this long before now; its card record follows a minute later.
    static let laundryAgo: TimeInterval = 44 * 3600

    /// Synthetic balance, meter and card records, never later than `now` (whatever the device's
    /// time zone), written in the school's calendar as the school does. Meals sit at meal times
    /// (07:42, 12:16, 17:58) of the last days, so 最近 reads like a real week.
    static func snapshot(now: Date, read: Date, kwh: String, dailyKWh: String, balance: String = "86.50") -> HomeSnapshot {
        let school = SchoolCalendar.shanghai
        func record(at moment: Date, _ title: String, _ yuan: String, flag: String? = "1") -> CardRecord {
            let t = school.dateComponents([.hour, .minute, .second], from:moment)
            return CardRecord(date:SchoolCalendar.dayString(moment, calendar:school),
                              time:String(format:"%02d%02d%02d", t.hour ?? 0, t.minute ?? 0, t.second ?? 0), title:title,
                              amount:Money(yuanString:yuan)!, balanceAfter:nil, direction:flag)
        }
        let range = CardActivity.range(at:now)
        var s = HomeSnapshot()
        s.card.succeed(Money(yuanString:balance)!, at:read)
        s.power.succeed(Meter(comAddress:"demo-meter", name:"3栋108", remainingKWh:Decimal(string:kwh),
                              dailyUseKWh:Decimal(string:dailyKWh)), at:read)
        let today = school.startOfDay(for:now)
        func at(_ hour: Int, _ minute: Int, daysBack: Int) -> Date {
            let day = school.date(byAdding:.day, value:-daysBack, to:today) ?? today
            return school.date(bySettingHour:hour, minute:minute, second:0, of:day) ?? day
        }
        let meals = [(7, 42, "POS消费示例早餐铺", "4.50"), (12, 16, "POS消费示例面馆", "12.00"), (17, 58, "POS消费示例面馆", "9.00")]
        var records = (0..<3).flatMap { back in meals.map { meal in record(at:at(meal.0, meal.1, daysBack:back), meal.2, meal.3) } }
            .filter { ($0.moment(calendar:school) ?? now) <= now.addingTimeInterval(-15 * 60) }
        records.append(record(at:now.addingTimeInterval(-showerAgo + 60), "蓝牙热水", "1.32"))
        // The demo laundry order, as the card has it a minute after it was paid.
        records.append(record(at:now.addingTimeInterval(-laundryAgo + 60), "洗衣", "4.00"))
        records.append(record(at:at(13, 5, daysBack:1), "校园卡充值", "50.00", flag:nil))
        // A lunch paid with WeChat, as the home read keeps it once its two records are paired.
        var wechat = record(at:at(11, 48, daysBack:1), "POS消费(示例饭堂POS)(示例饭堂POS)02档口示例盖饭", "16.00")
        wechat.paidWithWeChat = true
        records.append(wechat)
        records.sort { ($0.moment(calendar:school) ?? now) > ($1.moment(calendar:school) ?? now) }
        s.activity.succeed(CardActivity(records:records, begin:range.begin, end:range.end, complete:true), at:read)
        s.roomLabel = "3栋108"
        return s
    }
}
#endif
