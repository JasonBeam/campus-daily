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
            case .running(let program, let end): return program + " · " + CampusFormat.clock(end) + " 洗完"
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
    struct Segment { let text: String; var color: ThemeColor? = nil }

    var signedIn = true
    /// Settings › 学校账号 (nil after a web sign-in by someone not known to be the same person).
    var schoolAccount: SchoolAccount?
    var passwordSaved: Bool { schoolAccount?.password != nil }
    /// DEBUG demo only: why Settings › 高级 › 重置校日常 is locked (the live value comes from the shower).
    var resetLock: AppReset.Lock?
    /// DEBUG demo only: why the 主题 options are greyed out (the live value comes from the
    /// shower and laundry models), and whether settings opens on the 主题 page.
    var themeLock: ThemeLock?
    var themePageShown = false
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
        lines = ReminderKey.lines(in:campus.services.defaults)

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
