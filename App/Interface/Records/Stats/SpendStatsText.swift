//
//  SpendStatsText.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import Foundation
import Core

/// The records page stats' words in either theme (Camo's copy: 暖橙 spoken and with 。, 清爽
/// written and with ；). Amounts come as `Part`s so the view can set them in ink, semibold.
struct SpendStatsText {
    /// A run of a line: an amount (`strong`) or the words around it.
    struct Part: Equatable {
        var text: String
        var strong = false
    }

    let theme: AppTheme
    /// The records' calendar (the school's, or the sample's): days are named in it.
    let calendar: Calendar

    private var warm: Bool { theme != .clear }

    // MARK: Switch and totals

    static func spanName(_ span: SpendSpan) -> String {
        switch span {
        case .week: return "7 天"
        case .month: return "30 天"
        case .term: return "本学期"
        }
    }

    /// 「7 天花了」 / 「合计」.
    func totalLabel(_ span: SpendSpan) -> String {
        warm ? Self.spanName(span) + "花了" : "合计"
    }

    /// 「平均每天 ¥17.63 · 比前 7 天多花了 ¥12.30」 / 「日均 ¥17.63 · 较前 7 天 +¥12.30」; the
    /// comparison only when the stats have one (never for this term).
    func averageLine(_ stats: SpendStats) -> [Part] {
        var parts = [Part(text:warm ? "平均每天 " : "日均 "), Part(text:Self.yuan(stats.dailyAverage), strong:true)]
        if let versus = stats.versusPrevious, stats.span != .term {
            let span = Self.spanName(stats.span)
            if Self.aboutSame(versus) {
                parts.append(Part(text:warm ? " · 和前 \(span)差不多" : " · 与前 \(span)持平"))
            } else if warm {
                parts.append(Part(text:" · 比前 \(span)" + (versus.fen > 0 ? "多花了 " : "少花了 ")))
                parts.append(Part(text:Self.yuan(Self.magnitude(versus)), strong:true))
            } else {
                parts.append(Part(text:" · 较前 \(span) "))
                parts.append(Part(text:Self.signed(versus), strong:true))
            }
        }
        return parts
    }

    /// The total, average and comparison as one VoiceOver label.
    func spokenSummary(_ stats: SpendStats) -> String {
        var words = warm
            ? "\(totalLabel(stats.span)) \(stats.total.yuanText) 元，平均每天 \(stats.dailyAverage.yuanText) 元"
            : "合计 \(stats.total.yuanText) 元，日均 \(stats.dailyAverage.yuanText) 元"
        if let versus = stats.versusPrevious, stats.span != .term {
            let span = Self.spanName(stats.span)
            let amount = Self.magnitude(versus).yuanText
            if Self.aboutSame(versus) {
                words += warm ? "，和前 \(span)差不多" : "，与前 \(span)持平"
            } else if warm {
                words += "，比前 \(span)" + (versus.fen > 0 ? "多花 " : "少花 ") + amount + " 元"
            } else {
                words += "，较前 \(span)" + (versus.fen > 0 ? "多 " : "少 ") + amount + " 元"
            }
        }
        return words
    }

    // MARK: One bar

    /// What the bar is: 「11月19日 周四」, or 「11月17日那周」 / 「11月17日起一周」 for a week.
    func barName(_ bar: SpendBar) -> String {
        guard let first = bar.days.first.flatMap(day) else { return "" }
        let date = SchoolCalendar.dayTitle(first, calendar:calendar)
        if bar.days.count > 1 { return warm ? date + "那周" : date + "起一周" }
        return date + " " + SchoolCalendar.weekday(first, calendar:calendar)
    }

    /// The label over the big number while a bar is looked at: 「11月19日 周四 花了」 /
    /// 「11月19日 周四」, 「今天到现在花了」 / 「今日至今」 for today. For a bar without spending
    /// see `nothingSpent`.
    func barLabel(_ bar: SpendBar) -> String {
        if bar.isCurrent {
            if bar.days.count > 1 { return warm ? "本周到现在花了" : "本周至今" }
            return warm ? "今天到现在花了" : "今日至今"
        }
        if bar.spent == .zero { return barName(bar) }
        return warm ? barName(bar) + " 花了" : barName(bar)
    }

    /// In the big number's place for a bar (or a span) without spending.
    var nothingSpent: String { warm ? "没花钱" : "无支出" }

    /// The line under a looked-at day: against the span's daily average; nil for today (not over
    /// yet), a day without spending and a week (a week's total doesn't compare with a day's).
    func barLine(_ bar: SpendBar, average: Money) -> [Part]? {
        if bar.unsure {
            let words = bar.days.count > 1
                ? (warm ? "这周的记录学校没给全，可能不准。" : "该周记录不完整")
                : (warm ? "这天的记录学校没给全，可能不准。" : "该日记录不完整")
            return [Part(text:words)]
        }
        guard !bar.isCurrent, bar.spent != .zero, bar.days.count == 1 else { return nil }
        let difference = bar.spent - average
        if Self.aboutSame(difference) { return [Part(text:warm ? "和平均每天差不多" : "与日均持平")] }
        if warm {
            return [Part(text:difference.fen > 0 ? "比平均每天多花 " : "比平均每天少花 "),
                    Part(text:Self.yuan(Self.magnitude(difference)), strong:true)]
        }
        return [Part(text:"较日均 "), Part(text:Self.signed(difference), strong:true)]
    }

    /// The chart's VoiceOver value for a bar: 「11月19日，32.10 元」.
    func spokenBar(_ bar: SpendBar) -> String {
        guard let first = bar.days.first.flatMap(day) else { return "" }
        let date = SchoolCalendar.dayTitle(first, calendar:calendar)
        let name = bar.days.count > 1 ? (warm ? date + "那周" : date + "起一周") : date
        var words = "\(name)，\(bar.spent.yuanText) 元"
        if bar.isCurrent { words += bar.days.count > 1 ? "，本周还没过完" : "，今天还没过完" }
        if bar.unsure { words += "，记录可能不全" }
        return words
    }

    // MARK: States and notes

    /// In the big number's place while reading.
    func loading(_ span: SpendSpan) -> String {
        guard span == .term else { return "正在读记录…" }
        return warm ? "正在读本学期的记录，要多等一会儿…" : "正在读取本学期记录，请稍候…"
    }

    static let failed = "没读到记录，下拉再试。"

    /// In the big number's place when nothing was spent in the span.
    func empty(_ span: SpendSpan) -> String {
        guard warm else { return "本期无支出" }
        switch span {
        case .week: return "这 7 天没用校园卡花钱。"
        case .month: return "这 30 天没用校园卡花钱。"
        case .term: return "本学期没用校园卡花钱。"
        }
    }

    func unsureDays(_ count: Int) -> String {
        warm ? "有 \(count) 天的记录学校没给全，这个数可能不准。" : "\(count) 天记录不完整；数据仅供参考"
    }

    /// The school's records stop before the span: 「学校只给到 10月8日的记录，从那天算起。」
    func coveredFrom(_ yyyyMMdd: String) -> String? {
        guard let date = day(yyyyMMdd) else { return nil }
        let title = SchoolCalendar.dayTitle(date, calendar:calendar)
        return warm ? "学校只给到 \(title)的记录，从那天算起。" : "记录仅可读取至 \(title)；统计自该日起"
    }

    var footnote: String {
        warm ? "只算校园卡上的钱，不算充值和退款；洗衣用支付宝付的不在里面。"
             : "仅统计校园卡支出，不含充值、退款及支付宝洗衣订单"
    }

    // MARK: Term start

    /// 「9月1日起 · 」+「改开学日」 / 「自 9月1日 起；可」+「修改」.
    func termRange(_ start: Date) -> (text: String, action: String) {
        let title = SchoolCalendar.dayTitle(start, calendar:calendar)
        return warm ? (title + "起 · ", "改开学日") : ("自 \(title) 起；可", "修改")
    }

    func spokenTermRange(_ start: Date) -> String {
        "本学期从 \(SchoolCalendar.dayTitle(start, calendar:calendar)) 算起，" + (warm ? "改开学日" : "修改开学日")
    }

    var termSheetTitle: String { "开学日" }
    var termPickerTitle: String { warm ? "这学期哪天开学？" : "本学期开学日期" }
    var termFootnote: String {
        warm ? "「本学期」从这天算起。没改过的话，春季按 3月1日、秋季按 9月1日。"
             : "「本学期」自该日起统计；默认春季 3月1日、秋季 9月1日"
    }
    func termRestore(_ defaultStart: Date) -> String {
        let title = SchoolCalendar.dayTitle(defaultStart, calendar:calendar)
        return warm ? "用回 \(title)" : "恢复默认（\(title)）"
    }

    // MARK: Categories

    /// 「¥86」: whole yuan, halves up.
    static func wholeYuan(_ money: Money) -> String {
        "¥" + grouped((money.fen + 50) / 100)
    }

    /// 「70%」, 「<1%」 for a share under half a percent but above nothing.
    static func percent(_ fraction: Double) -> String {
        let value = Int((fraction * 100).rounded())
        return value < 1 && fraction > 0 ? "<1%" : "\(value)%"
    }

    /// A category's capsule to VoiceOver: 「电费，40 元」, and its share of those counted when it
    /// is counted: 「食堂，86.40 元，占 70%」.
    static func spokenShare(_ share: SpendShare) -> String {
        let words = "\(share.kind.title)，\(spokenYuan(share.spent)) 元"
        guard share.included else { return words }
        let value = Int((share.fraction * 100).rounded())
        let part = value < 1 && share.fraction > 0 ? "不到 1%" : "\(value)%"
        return words + "，占 \(part)"
    }

    /// Under the capsules, both themes.
    static let categoryNote = "电费是整个宿舍一起交的，默认不算；点上面的分类可以加回来或拿掉。"

    /// A capsule's VoiceOver value: counted or not.
    static func categoryValue(_ share: SpendShare) -> String { share.included ? "算进统计" : "不算" }

    /// A capsule's VoiceOver hint: the last one counted can't be turned off.
    static func categoryHint(_ share: SpendShare, counted: Set<CardRecordKind>) -> String {
        isLastCounted(share, counted:counted) ? "至少要留一类，这一类拿不掉" : "轻点两下，加进或拿出统计"
    }

    /// The only category counted of all kept (`counted`, listed in the span or not):
    /// `CardRecordsModel.toggleCategory` refuses to turn it off.
    static func isLastCounted(_ share: SpendShare, counted: Set<CardRecordKind>) -> Bool {
        share.included && counted == [share.kind]
    }

    /// Spent in the span, but only on categories left out (those counted had nothing in it):
    /// every capsule shown is off.
    static func nothingCounted(_ stats: SpendStats) -> Bool {
        stats.isEmpty && stats.shares.contains { !$0.included && $0.spent > .zero }
    }

    /// In the chart's place when `nothingCounted`, both themes; the capsules are under it.
    static let nothingCountedNote = "这段时间里，算进统计的分类都没花钱；点下面的分类加进来。"

    /// Read out after a capsule is switched: the new total, as the label says it — 「7 天花了 383 元」
    /// / 「合计 383 元」; with nothing counted spent, the ¥0 total and then the chart's words; the
    /// empty words when nothing at all was spent.
    func spokenTotal(_ stats: SpendStats) -> String {
        if Self.nothingCounted(stats) { return spokenAmount(stats) + "。" + Self.nothingCountedNote }
        if stats.isEmpty { return empty(stats.span) }
        return spokenAmount(stats)
    }

    /// The total alone, as the label says it: 「7 天花了 383 元」 / 「合计 383 元」.
    func spokenAmount(_ stats: SpendStats) -> String {
        (warm ? totalLabel(stats.span) + " " : "合计 ") + Self.spokenYuan(stats.total) + " 元"
    }

    /// 「40」, 「40.50」: whole yuan without the fen when there are none.
    static func spokenYuan(_ money: Money) -> String {
        money.fen % 100 == 0 ? String(money.fen / 100) : money.yuanText
    }

    // MARK: Amounts

    /// 「¥1,504.90」.
    static func yuan(_ money: Money) -> String { "¥" + number(money) }

    /// 「1,504.90」: the big number without its ¥.
    static func number(_ money: Money) -> String {
        let fen = money.fen.magnitude
        return (money.fen < 0 ? "−" : "") + grouped(Int(fen / 100)) + "." + String(format:"%02d", Int(fen % 100))
    }

    /// 「+¥12.30」 / 「−¥12.30」 (a true minus, U+2212, as wide as the plus).
    static func signed(_ money: Money) -> String {
        (money.fen < 0 ? "\u{2212}" : "+") + yuan(magnitude(money))
    }

    /// Less than ¥1 apart: 「差不多」 / 「持平」.
    static func aboutSame(_ difference: Money) -> Bool { difference.fen.magnitude < 100 }

    private static func magnitude(_ money: Money) -> Money { Money(fen:Int(money.fen.magnitude)) }

    private static func grouped(_ value: Int) -> String {
        var digits = String(value.magnitude)
        var out = ""
        while digits.count > 3 {
            out = "," + digits.suffix(3) + out
            digits = String(digits.dropLast(3))
        }
        return (value < 0 ? "-" : "") + digits + out
    }

    /// `yyyyMMdd` → that day's start in the school's calendar.
    func day(_ yyyyMMdd: String) -> Date? {
        guard yyyyMMdd.count == 8, let value = Int(yyyyMMdd) else { return nil }
        return calendar.date(from:DateComponents(year:value / 10000, month:value / 100 % 100, day:value % 100))
    }
}
