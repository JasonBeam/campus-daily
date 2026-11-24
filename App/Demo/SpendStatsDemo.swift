//
//  SpendStatsDemo.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

#if DEBUG
import Foundation
import Core

/// campusdaily://demo/stats/<state> — 校园卡记录 (暖橙) or 订单 (清爽) over the records list demo,
/// its spending stats:
/// - `s7` / `s30` / `sem`: the sample records' own stats on 7 天, 30 天, 本学期 (the span is
///   kept, as a tap on it would);
/// - `day`: the sample's 7 天, looking at its biggest day, as while pressing the bars;
/// made up rather than worked out (synthetic amounts, today's dates), the span switch working
/// on them and 改开学日 changing nothing:
/// - `load`: 本学期 still reading; `empty`: 7 天 with nothing spent; `failed`: the read failed;
/// - `notes`: 30 天 with two unsure days and the school's records starting late.
enum SpendStatsDemo: String {
    case s7, day, s30, sem, load, empty, failed, notes

    /// Its stats are made up, not the sample records' own.
    var madeUp: Bool { ![.s7, .day, .s30, .sem].contains(self) }

    /// The one a link last asked for; nil once an ordinary records demo opens.
    @MainActor static var current: SpendStatsDemo?

    static func handle(_ url: URL) -> SpendStatsDemo? {
        guard url.scheme == "campusdaily", url.host == "demo" else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        guard parts.first == "stats", parts.count > 1 else { return nil }
        return SpendStatsDemo(rawValue:parts[1])
    }

    var span: SpendSpan {
        switch self {
        case .s7, .day, .empty, .failed: return .week
        case .s30, .notes: return .month
        case .sem, .load: return .term
        }
    }

    func phase(_ span: SpendSpan, now: Date = Date()) -> SpendStatsView.Phase {
        switch self {
        case .load: return .loading
        case .failed: return .failed
        default: return .loaded(Self.stats(span, empty:self == .empty, notes:self == .notes, now:now))
        }
    }

    static func termStart(now: Date = Date()) -> Date {
        let calendar = SchoolCalendar.shanghai
        let parts = calendar.dateComponents([.year, .month], from:now)
        let year = parts.year ?? 2026, month = parts.month ?? 1
        let (y, m) = (3...8).contains(month) ? (year, 3) : (month < 3 ? year - 1 : year, 9)
        return calendar.date(from:DateComponents(year:y, month:m, day:1)) ?? now
    }

    // MARK: Made-up stats

    private static let week = [1820, 1260, 3210, 970, 2200, 1520, 1360]
    private static let month = [1180, 1240, 1710, 1130, 2010, 1450, 0, 1120, 1780, 1650, 0,
                                 2280, 1150, 1400, 1090, 1790, 1210, 1580, 1650, 1260, 980,
                                 720, 1430, 1760, 1300, 3200, 1100, 1920, 1550, 1700]
    private static let weeks = [13870, 12880, 12320, 11960, 4900, 7400, 11890, 11730, 10750, 11430, 10200, 12720, 4310]

    static func stats(_ span: SpendSpan, empty: Bool, notes: Bool, now: Date) -> SpendStats {
        let shape = SpendBarsPlaceholder.bars(span, termStart:termStart(now:now), now:now)
        let amounts = span == .week ? week : span == .month ? month : weeks
        let bars = shape.enumerated().map { index, bar in
            var bar = bar
            bar.spent = Money(fen:empty ? 0 : amounts[index % amounts.count])
            bar.unsure = notes && span != .term && (index == 20 || index == 21)
            return bar
        }
        let days = bars.reduce(0) { $0 + $1.days.count }
        let total = bars.reduce(Money.zero) { $0 + $1.spent }
        let average = Money(fen:Int((Double(total.fen) / Double(max(days, 1))).rounded()))
        let versus: Money? = empty || span == .term ? nil : Money(fen:span == .week ? 1230 : -2160)
        return SpendStats(span:span, total:total, dailyAverage:average, versusPrevious:versus, bars:bars,
                          shares:shares(total, term:span == .term), unsureDays:notes ? 2 : 0,
                          coveredFrom:notes ? bars.first?.id : nil,
                          termStart:span == .term ? SchoolCalendar.dayString(termStart(now:now), calendar:SchoolCalendar.shanghai) : nil)
    }

    /// 食堂 70%, 热水 18%, 电费 8%, (洗衣 on the term), 其他 the rest.
    private static func shares(_ total: Money, term: Bool) -> [SpendShare] {
        guard total.fen > 0 else { return [] }
        let parts: [(CardRecordKind, Double)] = term
            ? [(.canteen, 0.6725), (.shower, 0.178), (.electricity, 0.0797), (.laundry, 0.0053)]
            : [(.canteen, 0.7), (.shower, 0.178), (.electricity, 0.081)]
        var shares: [SpendShare] = []
        var left = total.fen
        for (kind, fraction) in parts {
            let fen = Int((Double(total.fen) * fraction).rounded())
            left -= fen
            shares.append(SpendShare(kind:kind, spent:Money(fen:fen), fraction:Double(fen) / Double(total.fen)))
        }
        shares.append(SpendShare(kind:.other, spent:Money(fen:left), fraction:Double(left) / Double(total.fen)))
        return shares
    }
}
#endif
