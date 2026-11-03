import Foundation
import SwiftUI
import Core

/// Everything the home screen shows, derived from the models (or DEBUG demo data).
struct HomeData {
    typealias Shower = ShowerHomeStatus
    /// Home 洗衣 row.
    enum Laundry: Equatable {
        case unknown, idle, unpaid, starting, done, inUse, unresolved
        case running(program: String, end: Date)
        case unavailable(LaundryFacts.Unavailable)
        var subtitle: String {
            switch self {
            case .unknown, .idle: return "常用"
            case .unpaid: return "订单还没付款"
            case .starting: return "已付款，等机器启动"
            case .running(let program, let end): return program + " · " + LaundryFormat.clock(end) + " 洗完"
            case .done: return "刚刚洗完"
            case .inUse: return "有人在用"
            case .unavailable(.offline): return "机器离线"
            case .unavailable(.broken): return "机器故障"
            case .unavailable(.disabled): return "机器停用"
            case .unresolved: return "上次订单还没确认"
            }
        }
        var value: RowValue? {
            switch self {
            case .unknown, .unavailable: return nil
            case .idle: return .word("空闲")
            case .unpaid: return .word("待付款")
            case .starting: return .word("启动中")
            case .running(_, let end): return .countdown(end:end)
            case .done: return .word("洗好了")
            case .inUse: return .word("使用中")
            case .unresolved: return .accentWord("待核对")
            }
        }
        /// VoiceOver words for the trailing value.
        func spokenValue(now: Date = Date()) -> String? {
            switch value {
            case .word(let word)?, .accentWord(let word)?: return word
            case .countdown(let end)?: return "还剩 \(LaundryFormat.minutesLeft(until:end, now:now)) 分钟"
            default: return nil
            }
        }
    }
    struct LaundryDone: Equatable {
        let id: String
        let amount: Decimal?
        let detail: String
    }
    /// One run of a sentence with its own colour (the laundry page's hero).
    struct Segment { let text: String; var color: Color? = nil }

    var signedIn = true
    /// Settings › 学校账号 (nil after a web sign-in by someone not known to be the same person).
    var schoolAccount: SchoolAccount?
    var passwordSaved: Bool { schoolAccount?.password != nil }
    /// DEBUG demo only: why Settings › 高级 › 重置校日常 is locked (the live value comes from the shower).
    var resetLock: AppReset.Lock?
    var dorm: String?
    /// Settings: 「校区 · 公寓 · 楼栋 · 房间」 of the dorm and of the bound meter (they can differ).
    var dormLocation: String?
    var meterLocation: String?
    var powerBound = true
    /// No meter bound and the automatic lookup is running.
    var findingMeter = false
    /// Balance, meter and card records with their own read times and errors.
    var snapshot = HomeSnapshot()
    var lines = ReminderLines()
    /// A school refresh is running (this process).
    var refreshing = false
    /// Refreshes keep ending without storing their numbers.
    var notSaving = false
    var shower = Shower.idle
    /// The last start failed (shown under the shower button instead of the last shower).
    var showerIssue: String?
    /// Showering, but the device never confirmed the authorization write (said under the button).
    var showerUnconfirmed = false
    var lastShowerMinutes: Int?
    var lastShowerCost: Decimal?
    /// 「学校洗衣机」 on. Off: no laundry row, no laundry in 最近, no done panel.
    var laundryEnabled = true
    /// The 学校洗衣机 switch can't be turned off yet (an order is unfinished).
    var laundryLocked = false
    var laundryBound = false
    var laundryMachine: String?
    var laundry = Laundry.unknown
    /// A recently finished order, for the once-per-order done panel.
    var laundryDone: LaundryDone?
    /// The app's own showers and laundry orders, merged with the card records in 最近.
    var appActivities: [AppActivity] = []

    func cardFigure(now: Date = Date()) -> HomeFigure {
        HomeFigures.card(snapshot, signedIn:signedIn, lines:lines, now:now)
    }
    func powerFigure(now: Date = Date()) -> HomeFigure {
        let meter: HomeFigure.MeterState = powerBound ? .bound : findingMeter ? .finding : .notFound
        return HomeFigures.power(snapshot, signedIn:signedIn, meter:meter, lines:lines, now:now)
    }
    var updateLine: HomeUpdateLine {
        HomeUpdateLine.of(snapshot, signedIn:signedIn, meterBound:powerBound, refreshing:refreshing,
                          loginHeld:schoolAccount?.isHolding(at:Date()) ?? false, notSaving:notSaving)
    }
    /// Newest first, more than fit (home cuts them to the screen); card records only while
    /// signed in (the snapshot is empty otherwise).
    var recents: [RecentItem] {
        RecentFeed.items(card:snapshot.activity.value?.records, app:recentActivities,
                         limit:RecentFeed.homeCandidates)
    }
    /// The app's own records 最近 and 校园卡记录 show: laundry only while 学校洗衣机 is on.
    var recentActivities: [AppActivity] {
        laundryEnabled ? appActivities : appActivities.filter { if case .laundry = $0.kind { return false }; return true }
    }
}

// MARK: - Live data

extension HomeData {
    @MainActor init(campus: CampusModel, shower model: ShowerModel, laundry: LaundryModel, now: Date = Date()) {
        signedIn = campus.configured
        schoolAccount = campus.account
        dorm = Theme.dorm(campus.room)
        dormLocation = campus.profile?.dormLocation
        meterLocation = campus.profile?.meterLocation
        snapshot = campus.snapshot
        powerBound = campus.powerConfigured
        findingMeter = campus.matchingPower
        refreshing = campus.loading
        notSaving = campus.notSaving
        lines = ReminderKey.lines

        let state = model.state
        if !model.configured { shower = .unconfigured }
        else if state.mayBeFlowing, state.stateReviewRequired { shower = .needsCheck }
        else if state.canFinish, let start = model.sessionStarted { shower = model.busy ? .settling(start) : .showering(start) }
        else if let start = state.startedAt, state.phase == .closing || state.phase == .settling { shower = .settling(start) }
        else if state.phase == .authorizing || (model.busy && (state.phase == .idle || state.phase == .done)) { shower = .starting }
        else if state.phase == .failed, state.failure?.needsReview == true {
            shower = .unresolved(ShowerHomeReview(state.failure))
        }
        else if model.platformMissing { shower = .unavailable(ShowerModel.platformMissingText) }
        else { shower = .idle }
        if model.problem, shower == .idle { showerIssue = model.status }
        showerUnconfirmed = state.phase == .writePending && shower.showering != nil
        var activities: [AppActivity] = []
        // Minutes of water (from 出水, as the timer counted), not from the 开始洗澡 tap.
        if state.phase == .done, let start = model.sessionStarted, let end = model.lastEnded, let minutes = state.minutes {
            lastShowerMinutes = minutes; lastShowerCost = model.lastCost
            activities.append(AppActivity(id:"shower-\(start.timeIntervalSince1970)", kind:.shower(minutes:minutes),
                                          date:end, amount:model.lastCost.map { Money(yuan:$0) }))
        }

        laundryEnabled = laundry.schoolEnabled
        laundryLocked = laundry.schoolSwitchLocked
        laundryBound = laundry.configured
        if let device = laundry.snapshot { laundryMachine = device.deviceNo }
        let facts = LaundryFacts(model:laundry)
        self.laundry = Self.laundryRow(facts, now:now)
        laundryDone = laundryEnabled ? Self.laundryDone(facts, now:now) : nil
        if let record = laundry.checkout, record.inFlight, let created = record.createdAt {
            activities.append(AppActivity(id:"laundry-\(record.orderId ?? created.description)",
                                          kind:.laundry(program:record.programName), date:created,
                                          amount:facts.amount.map { Money(yuan:$0) },
                                          detail:record.draft.map { "\($0.machineName) 号机" }))
        }
        appActivities = activities
    }
}

extension HomeData {
    static func laundryRow(_ facts: LaundryFacts, now: Date = Date()) -> Laundry {
        switch facts.phase(now:now) {
        case .empty, .unknown: return .unknown
        case .idle: return .idle
        case .inUse: return .inUse
        case .unavailable(let kind): return .unavailable(kind)
        case .unpaid(let payable): return payable ? .unpaid : .unresolved
        case .starting: return .starting
        case .running(let end): return .running(program:facts.record?.programName ?? "洗衣", end:end)
        case .check: return .unresolved
        case .done: return .done
        }
    }
    static func laundryDone(_ facts: LaundryFacts, now: Date = Date()) -> LaundryDone? {
        guard let id = facts.doneOrderID(now:now), let record = facts.record else { return nil }
        let program = facts.recordProgram.map(LaundryFormat.program) ?? record.programName
        return LaundryDone(id:id, amount:facts.amount,
                           detail:[program, facts.machine.map(LaundryFormat.machine)].compactMap { $0 }.joined(separator:" · "))
    }
}

/// Settlement result panel content (a finished laundry order; the shower has its own page).
enum SettlementResult: Equatable {
    /// Laundry order 50: 「衣服洗好了」 · amount · 「标准洗 · 45 分钟 · 3 号机」.
    case laundryDone(amount: Decimal?, detail: String)
}

#if DEBUG
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
            var empty = HomeData(); empty.signedIn = false; empty.dorm = "3 栋 108"
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

/// campusdaily://demo/onboard/{1,1-filled,1-saved,1-loading,1-wrong,1-fallback,2,3,3-nolocation,3-missing,3-samename,
/// 3-samename-picked,4,4-checking,4-showering,4-unchecked,4-ok,4-miss,4-bt,4-busy,done}
/// Synthetic account and dorm; the primary button only moves to the next step.
enum OnboardingDemo {
    static func handle(_ url: URL) -> (OnboardingView.Step, OnboardingView.Preview)? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "onboard" else { return nil }
        var preview = OnboardingView.Preview(dorm:"3 栋 108")
        let name = parts.count > 1 ? parts[1] : "1"
        switch name {
        case "2": return (.washer, preview)
        case "3": preview.dormLocation = "北校区 · 东苑公寓 · 3 栋 · 108"; return (.dorm, preview)
        case "3-nolocation": return (.dorm, preview)
        case "3-missing": preview.dorm = nil; return (.dorm, preview)
        case "3-samename", "3-samename-picked":
            // Same-name meter picker: one name in two apartments, told apart by location.
            preview.powerChoices = [LocationChoice(id:"preview-0", title:"3 栋 108", location:"北校区 · 东苑公寓 · 3 栋 · 108"),
                                   LocationChoice(id:"preview-1", title:"3 栋 108", location:"北校区 · 西苑公寓 · 3 栋 · 108")]
            if name == "3-samename-picked" { preview.picked = "preview-1" }
            return (.dorm, preview)
        case "3-meter-finding", "3-meter-ask", "3-meter-ask-picked", "3-meter-slow", "3-meter-unfinished", "3-meter-ask-mixed":
            // The meter under the dorm (synthetic 99 栋 991): looking, two apartments to choose
            // from (one picked), the school too slow, one apartment not read, one apartment's room
            // and one halted before its rooms.
            preview.dorm = "99 栋 991"
            switch name {
            case "3-meter-finding": preview.meter = .finding
            case "3-meter-slow": preview.meter = .failed(MeterPageText.tooSlow)
            case "3-meter-unfinished": preview.meter = .failed(MeterPageText.unfinished(.apartment))
            case "3-meter-ask-mixed":
                if let question = MeterQuestion(CampusModel.demoMixedStop, address:CampusModel.demoAddress) { preview.meter = .ask(question) }
            default:
                if let question = MeterQuestion(CampusModel.demoApartmentStop, address:CampusModel.demoAddress) {
                    preview.meter = .ask(question)
                    if name == "3-meter-ask-picked" { preview.meterPicked = question.rows.last?.id }
                }
            }
            return (.dorm, preview)
        case "4": return (.water, preview)
        case "4-checking": preview.waterChecking = true; return (.water, preview)
        case "4-showering": preview.waterBlocked = ShowerModel.inspectionShoweringText; return (.water, preview)
        case "4-unchecked": preview.waterBlocked = ShowerModel.inspectionAwaitingCheckText; return (.water, preview)
        case "4-ok", "4-miss", "4-bt", "4-busy":
            preview.waterOutcome = ["4-ok":.verified, "4-miss":.notFound, "4-bt":.bluetoothOff, "4-busy":.inUse][name]
            return (.water, preview)
        case "1-filled", "1-loading", "1-wrong", "1-fallback":
            preview.account = "99100991"
            preview.password = name == "1-wrong" ? "" : "demo-password"
            preview.savePassword = name != "1-wrong"
            preview.loginState = ["1-loading":.loading, "1-wrong":.wrong, "1-fallback":.cannotDirect][name] ?? .idle
            return (.login, preview)
        case "1-saved":
            // A password saved on this phone: the account is filled in and the box ticked.
            preview.saved = SchoolAccount(account:"99100991", password:"demo-password")
            return (.login, preview)
        case "done": return (.done, preview)
        default: return (.login, preview)
        }
    }
}
#endif
