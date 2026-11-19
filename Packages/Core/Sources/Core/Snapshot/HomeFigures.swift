import Foundation

/// One of the two big numbers on the home screen (校园卡, 电量): the value, whether it is low
/// (red), and the small line under it. Pure; the home screen and its tests share it.
public struct HomeFigure: Sendable, Equatable {
    public enum Night: Sendable, Equatable { case tonight, tomorrow }
    /// 电量's meter: bound, being looked for automatically, or not found (yet).
    public enum MeterState: Sendable, Equatable { case bound, finding, notFound }
    public enum Subline: Sendable, Equatable {
        /// 「昨天花了 ¥12.00」
        case spent(Money)
        /// 「昨天没花钱」
        case spentNothing
        /// 「够用约 9 天」
        case lastsDays(Int)
        /// 「只够到今晚」/「只够到明晚」
        case lastsUntil(Night)
        /// 「登录后显示」
        case afterSignIn
        /// 「还没找到电表 · 去设置」
        case meterNotFound
        /// 「正在找电表…」 (with a spinner)
        case findingMeter

        public var text: String {
            switch self {
            case .spent(let money): return "昨天花了 " + money.description
            case .spentNothing: return "昨天没花钱"
            case .lastsDays(let days): return "够用约 \(days) 天"
            case .lastsUntil(.tonight): return "只够到今晚"
            case .lastsUntil(.tomorrow): return "只够到明晚"
            case .afterSignIn: return "登录后显示"
            case .meterNotFound: return "还没找到电表 · 去设置"
            case .findingMeter: return "正在找电表…"
            }
        }
    }

    /// Nil shows 「—」.
    public var value: Decimal?
    /// The number and the subline turn red. Never true without a value.
    public var low: Bool
    /// Nil hides the line (no gap is left).
    public var subline: Subline?

    public init(value: Decimal?, low: Bool, subline: Subline?) {
        self.value = value; self.low = low; self.subline = subline
    }

    /// 电量 without a meter, for VoiceOver (nil: the cell speaks its numbers).
    public var spokenPower: String? {
        switch subline {
        case .meterNotFound: return "电量，还没找到电表，去设置"
        case .findingMeter: return "电量，正在找电表"
        default: return nil
        }
    }

    /// False while the meter is being looked for: there is nothing to open yet.
    public var tappable: Bool { subline != .findingMeter }
}

/// The rules behind the two home numbers.
public enum HomeFigures {
    /// 校园卡: low under the user's card line; the subline is yesterday's spending, hidden
    /// whenever the records can't tell.
    public static func card(_ snapshot: HomeSnapshot, signedIn: Bool, lines: ReminderLines, now: Date,
                            calendar: Calendar = SchoolCalendar.shanghai) -> HomeFigure {
        guard signedIn else { return HomeFigure(value: nil, low: false, subline: .afterSignIn) }
        let value = snapshot.card.value?.yuan
        let spent = CardSpending.yesterday(snapshot.activity, now: now, calendar: calendar)
        let subline: HomeFigure.Subline? = spent.map { $0 == .zero ? .spentNothing : .spent($0) }
        return HomeFigure(value: value, low: value.map { $0 < lines.card } ?? false, subline: subline)
    }

    /// 电量: low under the user's power line or when the estimate is a day or less. The estimate
    /// (remaining ÷ the previous day's use, counted from the reading) needs a previous day's use
    /// above zero; without it the subline is hidden. Without a meter: 「—」 and whether it is
    /// being looked for or not found.
    public static func power(_ snapshot: HomeSnapshot, signedIn: Bool, meter: HomeFigure.MeterState = .bound,
                             lines: ReminderLines, now: Date,
                             calendar: Calendar = .current) -> HomeFigure {
        guard signedIn else { return HomeFigure(value: nil, low: false, subline: .afterSignIn) }
        switch meter {
        case .bound: break
        case .finding: return HomeFigure(value: nil, low: false, subline: .findingMeter)
        case .notFound: return HomeFigure(value: nil, low: false, subline: .meterNotFound)
        }
        guard let meter = snapshot.power.value, let remaining = meter.remainingKWh else {
            return HomeFigure(value: nil, low: false, subline: nil)
        }
        let estimate = self.estimate(remaining: remaining, dailyUse: meter.dailyUseKWh,
                                     readAt: snapshot.power.fetchedAt ?? now, now: now, calendar: calendar)
        let low = remaining < lines.power || (estimate.map { $0.days <= 1 } ?? false)
        var subline: HomeFigure.Subline?
        if let estimate {
            if low, let night = estimate.night { subline = .lastsUntil(night) }
            else { subline = .lastsDays(estimate.days) }
        }
        return HomeFigure(value: remaining, low: low, subline: subline)
    }

    /// Whole days left from `now` to the estimated end (rounded down; a reading two days old
    /// has two days fewer left) and, when the end falls today or tomorrow by `now`, which night.
    /// An end already past reads as tonight, with no days left.
    static func estimate(remaining: Decimal, dailyUse: Decimal?, readAt: Date, now: Date,
                         calendar: Calendar) -> (days: Int, night: HomeFigure.Night?)? {
        guard let dailyUse, dailyUse > 0, remaining >= 0 else { return nil }
        let daysLeft = NSDecimalNumber(decimal: remaining / dailyUse).doubleValue
        guard daysLeft.isFinite else { return nil }
        let end = readAt.addingTimeInterval(daysLeft * 86_400)
        let today = calendar.startOfDay(for: now)
        var night: HomeFigure.Night?
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           let after = calendar.date(byAdding: .day, value: 2, to: today) {
            if end < tomorrow { night = .tonight } else if end < after { night = .tomorrow }
        }
        let fromNow = max(0, end.timeIntervalSince(now) / 86_400)
        return (Int(fromNow.rounded(.down)), night)
    }
}

/// The line under the two numbers.
public enum HomeUpdateLine: Sendable, Equatable {
    /// Signed out: no line.
    case hidden
    /// 「正在更新…」 with a spinner.
    case refreshing
    /// 「10:32 更新」
    case updated(Date)
    /// 「没更新上，下拉再试 · 数字是 10:32 的」 (「昨天 10:32」, 「10月26日 10:32」 as on the widget);
    /// the date is nil when nothing was ever read.
    case failed(lastGood: Date?)
    /// 「登录过期了，点这里重新登录 · 数字是 10:32 的」: pulling again can't help, signing in can.
    case expired(lastGood: Date?)
    /// 「一直没更新上，重开 App 试试 · 数字是 10:32 的」: reads keep ending without the new
    /// numbers being stored (`InterruptionStreak`), so they only grow older.
    case notSaving(lastGood: Date?)

    /// Where tapping the expired line goes.
    public enum SignInTarget: Sendable, Equatable {
        /// The sign-in form.
        case signIn
        /// Settings › 学校账号: a password is saved but automatic sign-in is paused there.
        case account
    }

    public static func signInTarget(_ account: SchoolAccount?) -> SignInTarget {
        guard let account, let password = account.password, !password.isEmpty, account.paused else { return .signIn }
        return .account
    }

    /// Refreshing wins. Otherwise a failed read of the balance or of the bound meter (kept as
    /// the tile's error until a later read succeeds, so a refresh that stopped without reading
    /// changes nothing) shows the failed line. The time is the older of the shown numbers', so
    /// it never claims a number is fresher than it is (a number never read shows 「—」 and has
    /// no time). Nothing read and nothing failed yet (just signed in): no line.
    ///
    /// A login that has run out says so instead, except while automatic sign-in holds off after
    /// a password login that got no answer (`loginHeld`): that one resumes by itself, so it is
    /// still the plain failed line.
    ///
    /// Reads that keep failing to store their numbers (`notSaving`) leave no error on the tiles;
    /// they show their own line, after an expired login or a failed read.
    public static func of(_ snapshot: HomeSnapshot, signedIn: Bool, meterBound: Bool, refreshing: Bool,
                          loginHeld: Bool = false, notSaving: Bool = false) -> HomeUpdateLine {
        guard signedIn else { return .hidden }
        if refreshing { return .refreshing }
        var times = [snapshot.card.fetchedAt]
        if meterBound { times.append(snapshot.power.fetchedAt) }
        let lastGood = times.compactMap { $0 }.min()
        if snapshot.needsLogin, !loginHeld { return .expired(lastGood: lastGood) }
        if snapshot.card.error != nil || (meterBound && snapshot.power.error != nil) { return .failed(lastGood: lastGood) }
        if notSaving { return .notSaving(lastGood: lastGood) }
        guard let lastGood else { return .hidden }
        return .updated(lastGood)
    }

    /// Today 「10:32」, yesterday 「昨天 10:32」, earlier 「10月26日」.
    public static func stamp(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return UpdateTimeText.clock(date, calendar: calendar) }
        if UpdateTimeText.isYesterday(date, now: now, calendar: calendar) {
            return "昨天 " + UpdateTimeText.clock(date, calendar: calendar)
        }
        return UpdateTimeText.monthDay(date, calendar: calendar)
    }

    public func text(now: Date, calendar: Calendar) -> String? {
        switch self {
        case .hidden: return nil
        case .refreshing: return "正在更新…"
        case .updated(let date): return Self.stamp(date, now: now, calendar: calendar) + " 更新"
        case .failed(let date?): return "没更新上，下拉再试 · 数字是 " + UpdateTimeText.stamp(date, now: now, calendar: calendar) + " 的"
        case .failed(nil): return "没更新上，下拉再试"
        case .expired(let date?): return "登录过期了，点这里重新登录 · 数字是 " + UpdateTimeText.stamp(date, now: now, calendar: calendar) + " 的"
        case .expired(nil): return "登录过期了，点这里重新登录"
        case .notSaving(let date?): return "一直没更新上，重开 App 试试 · 数字是 " + UpdateTimeText.stamp(date, now: now, calendar: calendar) + " 的"
        case .notSaving(nil): return "一直没更新上，重开 App 试试"
        }
    }
}
