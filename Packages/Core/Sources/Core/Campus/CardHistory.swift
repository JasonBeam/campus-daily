import Foundation

/// One read of `card/getRecordList` for 校园卡记录: a range of whole school days (`yyyyMMdd`)
/// and one page of it, as the school pages a range by count.
public struct CardHistoryQuery: Sendable, Equatable {
    public var begin: String
    public var end: String
    public var page: Int
    public var pageSize: Int
    public init(begin: String, end: String, page: Int, pageSize: Int) {
        self.begin = begin; self.end = end; self.page = page; self.pageSize = pageSize
    }
}

/// 校园卡记录: the card's records read back from today, range by range of whole school days,
/// so a day never ends at a range boundary. Inside a range the school pages by count: the
/// range's pages are read one after another, and a day cut by a page boundary stays
/// incomplete until the range's next page came. Nothing is stored; a new page starts from
/// today again.
///
/// The school never says where the records begin, so the list ends after
/// `emptyRangesBeforeEnd` empty ranges in a row (longer than any holiday), or `maxDaysBack`.
public struct CardHistory: Sendable, Equatable {
    /// Days per range.
    public static let rangeDays = 14
    public static let pageSize = 50
    /// This many empty ranges in a row end the list (12 weeks).
    public static let emptyRangesBeforeEnd = 6
    /// A range needing more pages than this (or a page bringing nothing new while the school
    /// says there is more) is left there: the school is not paging as expected.
    public static let maxPagesPerRange = 20
    public static let maxDaysBack = 730

    let calendar: Calendar
    /// Start of the school's today.
    let today: Date
    /// Records of the ranges read to their end, then the current range's so far; each in the
    /// school's order (newest first).
    private var finished: [CardRecord] = []
    private var current: [CardRecord] = []
    /// Oldest day of the ranges read to their end.
    private var readFrom: String?
    /// Days of finished ranges that may still miss records (the school stopped paging).
    private var unsure: Set<String> = []
    /// Days with a record that may be on the list twice (no voucher, no balance): no total.
    private var mayRepeat: Set<String> = []
    /// Days back from today of the current range's last day.
    private var rangeEnd = 0
    private var page = 1
    private var emptyRanges = 0
    /// The current range came up short of the total the school gave for it.
    private var shortOfTotal = false
    /// The oldest day read when the first short page came: the records the school left out
    /// sit on that day or older, whatever the pages after it bring.
    private var shortCut: String?
    /// The school gave the current range a total below the rows it sent: its totals are not
    /// trusted for this range.
    private var wrongTotal = false
    /// No older records to ask for.
    public private(set) var reachedEnd = false

    public init(now: Date, calendar: Calendar = SchoolCalendar.shanghai) {
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
    }

    /// Every record read so far, newest range first; a meal paid with WeChat as one expense
    /// (`WeChatPairs`), its WeChat half left out while its day may still bring the other.
    public var records: [CardRecord] { WeChatPairs.merged(finished + current) { isRead(day: $0) } }

    /// Days back from today of the current range's first day: no further than `maxDaysBack`.
    private var rangeBegin: Int { min(rangeEnd + Self.rangeDays, Self.maxDaysBack) - 1 }

    func day(back: Int) -> String {
        SchoolCalendar.dayString(calendar.date(byAdding: .day, value: -back, to: today) ?? today, calendar: calendar)
    }

    /// The next page to ask for; nil at the end.
    public var nextQuery: CardHistoryQuery? {
        guard !reachedEnd else { return nil }
        return CardHistoryQuery(begin: day(back: rangeBegin), end: day(back: rangeEnd),
                                page: page, pageSize: Self.pageSize)
    }

    /// The oldest day read (fully or in part): the app's own records older than it wait for it.
    public var readThrough: String? {
        if let cut = cutDay { return cut }
        return readFrom
    }

    /// The oldest day of the current range so far, when its pages come newest first. Records
    /// without a readable date or time say nothing about where a page was cut.
    private var cutDay: String? {
        let dated = current.filter { $0.moment(calendar: calendar) != nil }
        guard !dated.isEmpty, Self.newestFirst(dated) else { return nil }
        return dated.map { Self.trimmed($0.date) }.min()
    }

    /// Every record of `day` (`yyyyMMdd`) has been read, each once.
    public func isComplete(day: String) -> Bool {
        if mayRepeat.contains(day) || unsure.contains(day) { return false }
        return isRead(day: day)
    }

    /// No more records of `day` will come: its range was read to its end (even when the school
    /// stopped paging early), or a later page of the current range is past it.
    func isRead(day: String) -> Bool {
        if let readFrom, day >= readFrom { return true }
        guard !reachedEnd, day >= self.day(back: rangeBegin), day <= self.day(back: rangeEnd),
              let cut = cutDay else { return false }
        if shortOfTotal { return shortCut.map { day > $0 } ?? false }
        return day > cut
    }

    /// Takes the school's answer to `query`; an answer to any other query is ignored.
    public mutating func receive(_ answer: CardRecordPage, for query: CardHistoryQuery) {
        guard let expected = nextQuery, query == expected else { return }
        // A record that came on the previous page too (a new one at the top pushed it down).
        let fresh = answer.rows.filter { row in !current.contains { $0.isSameRecord(as: row) } }
        current += fresh
        for row in fresh where row.cannotBeToldApart { mayRepeat.insert(Self.trimmed(row.date)) }
        // The total, when given, decides, unless it is below the rows sent (then it is wrong and
        // closes nothing); otherwise only a page with room left over is the last one.
        let last: Bool
        if let total = answer.total, (query.page - 1) * query.pageSize + answer.rows.count > total {
            wrongTotal = true
        }
        if let total = answer.total, !wrongTotal {
            last = answer.rows.isEmpty || query.page * query.pageSize >= total
            if answer.rows.count < query.pageSize && query.page * query.pageSize < total && !shortOfTotal {
                shortOfTotal = true
                shortCut = cutDay
            }
        } else {
            last = answer.rows.count < query.pageSize
        }
        let stuck = !last && (fresh.isEmpty || query.page >= Self.maxPagesPerRange)
        if !last && !stuck {
            page += 1
            return
        }
        if stuck || shortOfTotal || wrongTotal {
            // From the cut day back (the first short page's, when one came), this range's days
            // may miss records.
            let cut = shortOfTotal ? shortCut : cutDay
            for back in rangeEnd...rangeBegin {
                let d = day(back: back)
                if cut.map({ d <= $0 }) ?? true { unsure.insert(d) }
            }
        }
        emptyRanges = current.isEmpty ? emptyRanges + 1 : 0
        finished += current
        current = []
        readFrom = day(back: rangeBegin)
        rangeEnd += Self.rangeDays
        page = 1
        shortOfTotal = false
        shortCut = nil
        wrongTotal = false
        if emptyRanges >= Self.emptyRangesBeforeEnd || rangeEnd >= Self.maxDaysBack { reachedEnd = true }
    }

    /// What one 「load more」 brought: the history after it, and why it stopped early.
    public struct Load: Sendable {
        public var history: CardHistory
        /// The page that failed; asked for again by the next load. Rows read before stay.
        public var failure: ServiceError?
    }

    /// Reads pages until one brings rows to show, or the end. Empty ranges are read through
    /// in the same load (nothing new would appear to ask for more).
    public static func loadMore(_ history: CardHistory,
                                fetch: (CardHistoryQuery) async throws -> CardRecordPage) async -> Load {
        var h = history
        while let query = h.nextQuery {
            do {
                let answer = try await fetch(query)
                let before = h.records.count
                h.receive(answer, for: query)
                if h.records.count > before { break }
            } catch let e as ServiceError {
                return Load(history: h, failure: e)
            } catch {
                return Load(history: h, failure: .offline)
            }
        }
        return Load(history: h, failure: nil)
    }

    static func trimmed(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    static func newestFirst(_ rows: [CardRecord]) -> Bool {
        zip(rows, rows.dropFirst()).allSatisfy { trimmed($0.date) >= trimmed($1.date) }
    }
}

/// One day of 校园卡记录.
public struct CardDay: Sendable, Equatable, Identifiable {
    /// `yyyyMMdd`, school calendar.
    public var id: String
    /// 「今天」, 「昨天」, 「10月28日 周三」, 「2025年12月30日 周二」.
    public var title: String
    public var items: [RecentItem]
    /// Money out that day; nil when it can't be said (the day is not read to its end, it has no
    /// payment, a record may be in or out, or only the app's own records are shown).
    public var total: Money?

    /// 「花了 ¥23.50」.
    public var totalText: String? { total.map { "花了 ¥" + $0.yuanText } }
    /// VoiceOver: 「10月28日 周三，花了 23.50 元」.
    public var spokenTitle: String { total.map { title + "，花了 " + $0.yuanText + " 元" } ?? title }
}

/// 校园卡记录's day groups.
public enum CardDays {
    /// `history` nil = the school's records could not be read: the app's own showers and laundry
    /// orders only, without totals. Otherwise the same rows as 最近 (a shower or order the app
    /// still has carries its minutes or program), for the days read so far.
    public static func groups(history: CardHistory?, app: [AppActivity], now: Date,
                              calendar: Calendar = SchoolCalendar.shanghai) -> [CardDay] {
        var activities = app
        if let history {
            guard let from = history.readThrough else { return [] }
            activities = app.filter { SchoolCalendar.dayString($0.date, calendar: calendar) >= from }
        }
        let card = history?.records
        let items = RecentFeed.items(card: card, app: activities, limit: Int.max, calendar: calendar)
        var days: [CardDay] = []
        for item in items {
            let id = SchoolCalendar.dayString(item.date, calendar: calendar)
            if days.last?.id == id { days[days.count - 1].items.append(item); continue }
            // A day without a payment has no total.
            let total = history.flatMap { h in
                h.isComplete(day: id) ? spending(on: id, h.records, calendar: calendar).flatMap { $0.paid ? $0.total : nil } : nil
            }
            days.append(CardDay(id: id, title: title(day: item.date, now: now, calendar: calendar), items: [item], total: total))
        }
        return days
    }

    /// What was paid on `day` (`yyyyMMdd`, the school's calendar) by the school's records: the
    /// one rule behind 「昨天花了」 on home and each day's total in 校园卡记录. Money in (top-ups,
    /// refunds, grants) is left out; a payment's amount counts with its sign. `paid`: at least
    /// one payment. Nil when the records can't say: a record of that day whose time can't be
    /// read or that may be money in or out, or a record whose day can't be read at all.
    static func spending(on day: String, _ records: [CardRecord],
                         calendar: Calendar) -> (total: Money, paid: Bool)? {
        var total = Money.zero, paid = false
        for record in records {
            let recordDay = CardHistory.trimmed(record.date)
            guard record.moment(calendar: calendar) != nil else {
                // It may be that day's.
                if recordDay == day || recordDay.count != 8 || !recordDay.allSatisfy({ $0.isASCII && $0.isNumber }) { return nil }
                continue
            }
            guard recordDay == day else { continue }
            switch record.flow {
            case .moneyOut: total = total + record.amount; paid = true
            case .moneyIn: continue
            // A record that may be money in or out: no total rather than a wrong one.
            case .unknown: return nil
            }
        }
        return (total, paid)
    }

    /// 「今天」 / 「昨天」 / 「10月28日 周三」, with the year only outside the current one.
    public static func title(day: Date, now: Date, calendar: Calendar = SchoolCalendar.shanghai) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "昨天"
        }
        let year = calendar.component(.year, from: day)
        let prefix = year == calendar.component(.year, from: now) ? "" : "\(year)年"
        return prefix + SchoolCalendar.dayTitle(day, calendar: calendar) + " " + SchoolCalendar.weekday(day, calendar: calendar)
    }

    /// A row's time under its day: 「07:42」.
    public static func clock(_ date: Date, calendar: Calendar = SchoolCalendar.shanghai) -> String {
        let p = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", p.hour ?? 0, p.minute ?? 0)
    }
}
