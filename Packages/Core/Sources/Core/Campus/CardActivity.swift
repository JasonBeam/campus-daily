import Foundation

/// The school's calendar: card records carry Beijing-time dates and times without a zone, and
/// "yesterday" on the home screen is the school's yesterday.
public enum SchoolCalendar {
    public static var shanghai: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
        c.locale = Locale(identifier: "zh_CN")
        return c
    }

    /// 「10月28日」 for the home header: the school's day.
    public static func dayTitle(_ date: Date, calendar: Calendar = shanghai) -> String {
        let p = calendar.dateComponents([.month, .day], from: date)
        return "\(p.month ?? 0)月\(p.day ?? 0)日"
    }

    /// 「周二」 under it, on the same day.
    public static func weekday(_ date: Date, calendar: Calendar = shanghai) -> String {
        "周" + ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: date) - 1]
    }

    /// `yyyyMMdd` of `date` in `calendar`, the format of `card/getRecordList`'s `begin`/`end`.
    public static func dayString(_ date: Date, calendar: Calendar = shanghai) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}

/// One read of the card's recent records, as kept in the home snapshot.
public struct CardActivity: Sendable, Equatable, Codable {
    public var records: [CardRecord]
    /// First and last day asked for (`yyyyMMdd`, school calendar).
    public var begin: String
    public var end: String
    /// Every record of those days came back (the server's total fitted in the page). When not,
    /// a day's sum could miss records, so none is shown.
    public var complete: Bool

    public init(records: [CardRecord], begin: String, end: String, complete: Bool) {
        self.records = records; self.begin = begin; self.end = end; self.complete = complete
    }

    /// Records asked for per refresh: the day before yesterday through today, one page.
    public static let days = 3
    public static let pageSize = 50
    /// The records are asked for together with the balance and the meter, and given up this
    /// long after that request starts (not after the numbers are stored): the widget has about
    /// 20 s in all, and the balance and the meter are stored without waiting for them. On a
    /// network slow enough to miss it, 昨天花了 stays hidden.
    public static let timeout: TimeInterval = 6

    /// `begin`/`end` for a read at `now`.
    public static func range(at now: Date, calendar: Calendar = SchoolCalendar.shanghai) -> (begin: String, end: String) {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        return (SchoolCalendar.dayString(start, calendar: calendar), SchoolCalendar.dayString(now, calendar: calendar))
    }
}

/// What a card record was for, from the school's own name for it. Only these short names
/// reach the screen; the school's words (消费, POS, 圈存 …) never do.
public enum CardRecordKind: String, Sendable, Codable, CaseIterable {
    case canteen, shower, laundry, electricity, topUp, other

    public var title: String {
        switch self {
        case .canteen: return "食堂"
        case .shower: return "热水"
        case .laundry: return "洗衣"
        case .electricity: return "电费"
        case .topUp: return "充值"
        case .other: return "其他"
        }
    }

    /// The SF Symbol rows draw for it (grey, outline).
    public var symbol: String {
        switch self {
        case .canteen: return "fork.knife"
        case .shower: return "shower"
        case .laundry: return "washer"
        case .electricity: return "bolt"
        case .topUp: return "plus.circle"
        case .other: return "bag"
        }
    }

    /// Classifies by the record name (`transname`). Order matters: a hot-water name contains
    /// 「POS」 too, and paying for electricity or hot water from the card can be called
    /// 「电费充值」 or 「转入水控」, so those come before top-ups.
    /// WeChat's money in for a meal, left alone, is money in whatever its name (it can carry
    /// 「POS消费」): a top-up.
    public static func of(_ record: CardRecord) -> CardRecordKind {
        record.isWeChatHalf ? .topUp : of(name: record.title)
    }

    public static func of(name: String) -> CardRecordKind {
        let n = name.filter { !$0.isWhitespace }
        if n.contains("热水") || n.contains("水控") { return .shower }
        if n.contains("洗衣") { return .laundry }
        if n.contains("电费") || n.contains("购电") { return .electricity }
        if ["充值", "圈存", "转入"].contains(where: n.contains) { return .topUp }
        if n.hasPrefix("POS消费") || ["食堂", "饭堂", "餐厅"].contains(where: n.contains) { return .canteen }
        return .other
    }
}

public extension CardRecord {
    /// The record's moment in the school calendar; nil when the date or time can't be read.
    func moment(calendar: Calendar = SchoolCalendar.shanghai) -> Date? {
        let d = date.filter { !$0.isWhitespace }
        guard d.count == 8, d.allSatisfy(\.isASCII), let year = Int(d.prefix(4)),
              let month = Int(d.dropFirst(4).prefix(2)), let day = Int(d.suffix(2)) else { return nil }
        let t = time.filter { !$0.isWhitespace }
        guard t.count <= 6, t.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let clock = Int(t.isEmpty ? "0" : t) ?? 0
        let hour = clock / 10000, minute = clock / 100 % 100, second = clock % 100
        guard (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60 else { return nil }
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let moment = calendar.date(from: parts),
              calendar.component(.day, from: moment) == day else { return nil }
        return moment
    }

    var kind: CardRecordKind { CardRecordKind.of(self) }

    /// Money in or out. Direction flag 「1」 is a payment from the card, whatever the name says
    /// (「电费充值」 and 「转入水控」 take money out): out for a positive amount. Otherwise WeChat's
    /// money in for a meal (`isWeChatHalf`) and a name that says money came back or in (充值,
    /// 退款, 冲正, 补贴 …) are in, and without a flag any other positive amount is out. Anything
    /// else (a negative amount, another flag) can't be told apart and is `.unknown`.
    var flow: CardFlow {
        let flag = CardRecord.flag(direction)
        if flag == "1" { return amount.fen >= 0 ? .moneyOut : .unknown }
        if isWeChatHalf { return .moneyIn }
        let n = title.filter { !$0.isWhitespace }
        if CardFlow.incomeWords.contains(where: n.contains) { return .moneyIn }
        guard flag.isEmpty else { return .unknown }
        return amount.fen >= 0 ? .moneyOut : .unknown
    }
}

/// Which way a card record moved money.
public enum CardFlow: Sendable, Equatable {
    case moneyOut, moneyIn, unknown

    /// Names of money coming in: top-ups, and money given back or granted.
    static let incomeWords = ["充值", "圈存", "转入", "退款", "退费", "撤销", "冲正", "补助", "补贴"]
}

/// The useful part of a merchant name: 「POS消费(示例饭堂POS)(示例饭堂POS)01档口示例面馆」 →
/// 「示例面馆」. Nil when nothing useful is left (the row then shows only its time).
public enum MerchantName {
    /// Leading words that only say what kind of record it is.
    static let prefixes = ["POS消费", "消费", "蓝牙热水", "校园卡充值", "充值", "圈存", "转入", "购电", "电费", "洗衣"]
    /// A name that is only one of these adds nothing to the row title.
    static let generic: Set<String> = ["热水", "蓝牙热水", "洗衣", "电费", "购电", "充值", "食堂", "饭堂", "餐厅", "中卡"]
    /// Words never shown on screen.
    static let hidden = ["消费", "扣款", "POS", "圈存", "交易"]

    public static func clean(_ raw: String) -> String? {
        let (outside, groups) = splitParentheses(raw.filter { !$0.isWhitespace })
        if let main = useful(outside) { return main }
        // 「POS消费(示例饭堂POS)」: the name is only in the brackets.
        for group in groups.reversed() { if let inner = useful(group) { return inner } }
        return nil
    }

    static func useful(_ text: String) -> String? {
        var s = text.replacingOccurrences(of: "POS[0-9]*", with: "", options: .regularExpression)
        var stripped = true
        while stripped {
            stripped = false
            for p in prefixes where s.hasPrefix(p) && s.count > p.count {
                s.removeFirst(p.count); stripped = true
            }
        }
        if let stall = s.range(of: "档口", options: .backwards) { s = String(s[stall.upperBound...]) }
        s = String(s.drop { $0.isNumber || $0.isPunctuation || $0.isSymbol })
        s = s.trimmingCharacters(in: .punctuationCharacters)
        guard !s.isEmpty, !generic.contains(s), !prefixes.contains(s),
              !hidden.contains(where: s.contains), s.count <= 20 else { return nil }
        return s
    }

    /// Text outside any brackets (ASCII or full-width, nested), and each top-level group's text.
    static func splitParentheses(_ text: String) -> (String, [String]) {
        var outside = "", groups: [String] = [], current = "", depth = 0
        for ch in text {
            if ch == "(" || ch == "（" {
                depth += 1
                if depth > 1 { current.append(ch) }
            } else if (ch == ")" || ch == "）") && depth > 0 {
                depth -= 1
                if depth == 0 { groups.append(current); current = "" } else { current.append(ch) }
            } else if depth > 0 {
                current.append(ch)
            } else {
                outside.append(ch)
            }
        }
        return (outside, groups.map { splitParentheses($0).0 })
    }
}
