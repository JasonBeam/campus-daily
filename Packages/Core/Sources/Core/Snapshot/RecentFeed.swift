import Foundation

/// A shower or laundry order the app itself recorded, for 最近. The app maps its own records
/// to this (Snapshot does not know the shower or laundry state machines).
public struct AppActivity: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case shower(minutes: Int?)
        case laundry(program: String)
    }
    public var id: String
    public var kind: Kind
    /// When it ended (shower) or was paid (laundry).
    public var date: Date
    public var amount: Money?
    public var detail: String?

    public init(id: String, kind: Kind, date: Date, amount: Money?, detail: String? = nil) {
        self.id = id; self.kind = kind; self.date = date; self.amount = amount; self.detail = detail
    }

    var recordKind: CardRecordKind {
        switch kind {
        case .shower: return .shower
        case .laundry: return .laundry
        }
    }
}

/// One 最近 row.
public struct RecentItem: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable { case card, app }
    public var id: String
    public var kind: CardRecordKind
    /// 「食堂」, 「热水 · 11 分钟」, 「洗衣 · 标准洗」.
    public var title: String
    public var date: Date
    /// The merchant (card) or the app's own detail (「3 号机」).
    public var detail: String?
    public var amount: Money?
    public var source: Source
    /// For a card record, from its name, sign and flag; otherwise in for a top-up, else out.
    public var flow: CardFlow

    public init(id: String, kind: CardRecordKind, title: String, date: Date, detail: String?, amount: Money?,
                source: Source, flow: CardFlow? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.date = date
        self.detail = detail; self.amount = amount; self.source = source
        self.flow = flow ?? (kind == .topUp ? .moneyIn : .moneyOut)
    }

    public var symbol: String { kind.symbol }

    /// 「−¥12.00」 for money out, 「+¥50.00」 for money in, 「¥3.00」 (no sign) when that can't be told;
    /// nil without an amount.
    public var amountText: String? {
        guard let amount else { return nil }
        let value = Money(fen: abs(amount.fen))
        switch flow {
        case .moneyOut: return "−¥" + value.yuanText
        case .moneyIn: return "+¥" + value.yuanText
        case .unknown: return "¥" + value.yuanText
        }
    }

    /// VoiceOver: 「花了 12 元」 / 「进账 50 元」 / 「12 元」.
    public var spokenAmount: String? {
        guard let amount else { return nil }
        let value = Money(fen: abs(amount.fen))
        switch flow {
        case .moneyOut: return "花了 " + Self.spokenYuan(value) + " 元"
        case .moneyIn: return (kind == .topUp ? "充了 " : "进账 ") + Self.spokenYuan(value) + " 元"
        case .unknown: return Self.spokenYuan(value) + " 元"
        }
    }

    /// 「12」, 「1.32」, 「0.5」: no trailing zeros.
    public static func spokenYuan(_ money: Money) -> String {
        NSDecimalNumber(decimal: money.yuan).stringValue
    }
}

/// 最近: card records and the app's own records, newest first; the same shower or laundry
/// order appears once (the app's record, which knows the minutes or the program).
public enum RecentFeed {
    /// Rows given to home, which shows the whole ones that fit its screen (`RecentFit`).
    public static let homeCandidates = 20
    /// A card record this close to an app record of the same kind (and the same amount, when
    /// both are known) is the same shower or order.
    public static let sameEventWindow: TimeInterval = 30 * 60

    /// `card` nil = the records could not be read: only the app's records.
    public static func items(card: [CardRecord]?, app: [AppActivity], limit: Int,
                             calendar: Calendar = SchoolCalendar.shanghai) -> [RecentItem] {
        var cardItems: [(RecentItem, used: Bool)] = []
        for (index, record) in (card ?? []).enumerated() {
            guard let moment = record.moment(calendar: calendar) else { continue }
            let kind = record.kind
            let merchant = MerchantName.clean(record.title)
            let detail = record.paidWithWeChat ? [merchant, "微信支付"].compactMap { $0 }.joined(separator: " · ") : merchant
            let item = RecentItem(id: "card-\(record.date)\(record.time)-\(record.amount.fen)-\(index)", kind: kind,
                                  title: kind.title, date: moment, detail: detail,
                                  amount: record.amount, source: .card, flow: record.flow)
            cardItems.append((item, false))
        }
        var out: [RecentItem] = []
        for activity in app {
            let kind = activity.recordKind
            // The closest unused card record of the same event, if any, is dropped.
            let match = cardItems.indices
                .filter { i in
                    let c = cardItems[i]
                    return !c.used && c.0.kind == kind
                        && abs(c.0.date.timeIntervalSince(activity.date)) <= sameEventWindow
                        && (activity.amount == nil || c.0.amount == activity.amount)
                }
                .min { abs(cardItems[$0].0.date.timeIntervalSince(activity.date)) < abs(cardItems[$1].0.date.timeIntervalSince(activity.date)) }
            if let match { cardItems[match].used = true }
            let title: String
            switch activity.kind {
            case .shower(let minutes?): title = "热水 · \(minutes) 分钟"
            case .shower(nil): title = "热水"
            case .laundry(let program): title = program.isEmpty ? "洗衣" : "洗衣 · " + program
            }
            out.append(RecentItem(id: "app-" + activity.id, kind: kind, title: title, date: activity.date,
                                  detail: activity.detail, amount: activity.amount ?? match.flatMap { cardItems[$0].0.amount },
                                  source: .app))
        }
        out += cardItems.filter { !$0.used }.map(\.0)
        // Stable: equal times keep app records first, then the server's order.
        let sorted = out.enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date > b.element.date : a.offset < b.offset
        }
        return Array(sorted.map(\.element).prefix(max(0, limit)))
    }
}

/// 「昨天花了 ¥12.00」 / 「昨天没花钱」: the school calendar's yesterday, money out only.
public enum CardSpending {
    /// Nil when the records can't say: never read, read before today began (yesterday was not
    /// over yet), a range without yesterday, a page that did not hold every record, or a
    /// record of yesterday that may be money in or out. Money in (top-ups, refunds, grants)
    /// is left out; a payment's amount counts with its sign.
    public static func yesterday(_ activity: Tile<CardActivity>?, now: Date,
                                 calendar: Calendar = SchoolCalendar.shanghai) -> Money? {
        guard let activity, let read = activity.value, read.complete, let fetchedAt = activity.fetchedAt,
              fetchedAt >= calendar.startOfDay(for: now),
              let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        let yesterday = SchoolCalendar.dayString(yesterdayDate, calendar: calendar)
        guard read.begin <= yesterday, yesterday <= read.end else { return nil }
        var total = Money.zero
        for record in read.records {
            guard let moment = record.moment(calendar: calendar) else { return nil }
            guard calendar.isDate(moment, inSameDayAs: yesterdayDate) else { continue }
            switch record.flow {
            case .moneyOut: total = total + record.amount
            case .moneyIn: continue
            // A record that may be money in or out: no total rather than a wrong one.
            case .unknown: return nil
            }
        }
        return total
    }
}
