//
//  SpendStatsTextTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
import Core
@testable import XiaoRiChang

/// The records page stats' words (Camo's copy), in both themes.
final class SpendStatsTextTests: XCTestCase {
    let warm = SpendStatsText(theme:.warm)
    let clear = SpendStatsText(theme:.clear)

    func stats(_ span: SpendSpan = .week, total: Int = 12340, average: Int = 1763, versus: Int? = 1230) -> SpendStats {
        SpendStats(span:span, total:Money(fen:total), dailyAverage:Money(fen:average), versusPrevious:versus.map { Money(fen:$0) },
                   bars:[], shares:[], unsureDays:0, coveredFrom:nil, termStart:nil)
    }

    func bar(_ id: String = "20261119", fen: Int, current: Bool = false, unsure: Bool = false, days: [String]? = nil) -> SpendBar {
        SpendBar(id:id, days:days ?? [id], spent:Money(fen:fen), unsure:unsure, isCurrent:current, beforeStart:false, axisLabel:nil)
    }

    func joined(_ parts: [SpendStatsText.Part]?) -> String? { parts?.map(\.text).joined() }

    func testAverageLineComparesWithThePeriodBefore() {
        XCTAssertEqual(joined(warm.averageLine(stats())), "平均每天 ¥17.63 · 比前 7 天多花了 ¥12.30")
        XCTAssertEqual(joined(warm.averageLine(stats(.month, versus:-2160))), "平均每天 ¥17.63 · 比前 30 天少花了 ¥21.60")
        XCTAssertEqual(joined(clear.averageLine(stats())), "日均 ¥17.63 · 较前 7 天 +¥12.30")
        XCTAssertEqual(joined(clear.averageLine(stats(versus:-1230))), "日均 ¥17.63 · 较前 7 天 \u{2212}¥12.30")
        XCTAssertEqual(warm.averageLine(stats()).filter(\.strong).map(\.text), ["¥17.63", "¥12.30"])
    }

    func testLessThanAYuanApartIsAboutTheSame() {
        XCTAssertEqual(joined(warm.averageLine(stats(versus:99))), "平均每天 ¥17.63 · 和前 7 天差不多")
        XCTAssertEqual(joined(clear.averageLine(stats(versus:-99))), "日均 ¥17.63 · 与前 7 天持平")
        XCTAssertEqual(joined(warm.averageLine(stats(versus:100))), "平均每天 ¥17.63 · 比前 7 天多花了 ¥1.00")
    }

    func testTheTermAndAMissingPeriodHaveNoComparison() {
        XCTAssertEqual(joined(warm.averageLine(stats(.term, versus:500))), "平均每天 ¥17.63")
        XCTAssertEqual(joined(clear.averageLine(stats(versus:nil))), "日均 ¥17.63")
    }

    func testADayAgainstTheAverage() {
        let average = Money(fen:1763)
        XCTAssertEqual(joined(warm.barLine(bar(fen:3210), average:average)), "比平均每天多花 ¥14.47")
        XCTAssertEqual(joined(warm.barLine(bar(fen:316), average:average)), "比平均每天少花 ¥14.47")
        XCTAssertEqual(joined(clear.barLine(bar(fen:3210), average:average)), "较日均 +¥14.47")
        XCTAssertEqual(joined(clear.barLine(bar(fen:316), average:average)), "较日均 \u{2212}¥14.47")
        XCTAssertEqual(joined(warm.barLine(bar(fen:1800), average:average)), "和平均每天差不多")
        XCTAssertEqual(joined(clear.barLine(bar(fen:1700), average:average)), "与日均持平")
    }

    func testTodayIsNotComparedAndADayWithoutSpendingHasNoLine() {
        let average = Money(fen:1763)
        XCTAssertNil(warm.barLine(bar(fen:3210, current:true), average:average))
        XCTAssertEqual(warm.barLabel(bar(fen:1200, current:true)), "今天到现在花了")
        XCTAssertEqual(clear.barLabel(bar(fen:1200, current:true)), "今日至今")
        XCTAssertNil(clear.barLine(bar(fen:0), average:average))
        XCTAssertEqual(warm.barLabel(bar(fen:0)), "11月19日 周四")
        XCTAssertEqual(warm.nothingSpent, "没花钱")
        XCTAssertEqual(clear.nothingSpent, "无支出")
    }

    func testADayLabelAndItsUnsureLine() {
        XCTAssertEqual(warm.barLabel(bar(fen:4620)), "11月19日 周四 花了")
        XCTAssertEqual(clear.barLabel(bar(fen:4620)), "11月19日 周四")
        XCTAssertEqual(joined(warm.barLine(bar(fen:4620, unsure:true), average:Money(fen:1763))), "这天的记录学校没给全，可能不准。")
        XCTAssertEqual(joined(clear.barLine(bar(fen:4620, unsure:true), average:Money(fen:1763))), "该日记录不完整")
    }

    func testVoiceOverReadsABar() {
        XCTAssertEqual(warm.spokenBar(bar(fen:3210)), "11月19日，32.10 元")
        XCTAssertEqual(warm.spokenSummary(stats()), "7 天花了 123.40 元，平均每天 17.63 元，比前 7 天多花 12.30 元")
        XCTAssertEqual(clear.spokenSummary(stats(versus:-1230)), "合计 123.40 元，日均 17.63 元，较前 7 天少 12.30 元")
    }

    func testAmounts() {
        XCTAssertEqual(SpendStatsText.yuan(Money(fen:150490)), "¥1,504.90")
        XCTAssertEqual(SpendStatsText.number(Money(fen:12340)), "123.40")
        XCTAssertEqual(SpendStatsText.number(Money(fen:123456789)), "1,234,567.89")
        XCTAssertEqual(SpendStatsText.wholeYuan(Money(fen:8640)), "¥86")
        XCTAssertEqual(SpendStatsText.wholeYuan(Money(fen:8650)), "¥87")
        XCTAssertEqual(SpendStatsText.wholeYuan(Money(fen:101200)), "¥1,012")
        XCTAssertEqual(SpendStatsText.percent(0.004), "<1%")
        XCTAssertEqual(SpendStatsText.percent(0.7), "70%")
        XCTAssertEqual(SpendStatsText.spokenShare(SpendShare(kind:.canteen, spent:Money(fen:8640), fraction:0.7)), "食堂，86.40 元，占 70%")
    }

    func testStatesAndNotes() {
        XCTAssertEqual(warm.totalLabel(.week), "7 天花了")
        XCTAssertEqual(warm.totalLabel(.term), "本学期花了")
        XCTAssertEqual(clear.totalLabel(.month), "合计")
        XCTAssertEqual(warm.empty(.week), "这 7 天没用校园卡花钱。")
        XCTAssertEqual(clear.empty(.term), "本期无支出")
        XCTAssertEqual(warm.loading(.term), "正在读本学期的记录，要多等一会儿…")
        XCTAssertEqual(clear.loading(.week), "正在读记录…")
        XCTAssertEqual(warm.unsureDays(2), "有 2 天的记录学校没给全，这个数可能不准。")
        XCTAssertEqual(clear.coveredFrom("20261008"), "记录仅可读取至 10月8日；统计自该日起")
        XCTAssertEqual(warm.coveredFrom("20261008"), "学校只给到 10月8日的记录，从那天算起。")
    }

    func testTermStartWords() {
        let start = SchoolCalendar.shanghai.date(from:DateComponents(year:2026, month:9, day:1))!
        XCTAssertEqual(warm.termRange(start).text + warm.termRange(start).action, "9月1日起 · 改开学日")
        XCTAssertEqual(clear.termRange(start).text + clear.termRange(start).action, "自 9月1日 起；可修改")
        XCTAssertEqual(warm.termRestore(start), "用回 9月1日")
        XCTAssertEqual(clear.termRestore(start), "恢复默认（9月1日）")
    }

    func testPlaceholderBarsHaveTheSpansShape() {
        let calendar = SchoolCalendar.shanghai
        let now = calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:10))!
        let week = SpendBarsPlaceholder.bars(.week, termStart:now, now:now)
        XCTAssertEqual(week.map { $0.axisLabel ?? "" }, ["三", "四", "五", "六", "日", "一", "今天"])
        let month = SpendBarsPlaceholder.bars(.month, termStart:now, now:now)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(month.compactMap(\.axisLabel), ["10月26日", "11月10日", "今天"])
        let start = calendar.date(from:DateComponents(year:2026, month:9, day:1))!
        let term = SpendBarsPlaceholder.bars(.term, termStart:start, now:now)
        XCTAssertEqual(term.first?.days.first, "20260901")
        XCTAssertEqual(term.first?.days.count, 6)  // Tuesday 9月1日 through Sunday
        XCTAssertEqual(term.last?.axisLabel, "本周")
        XCTAssertEqual(term.compactMap(\.axisLabel), ["9月", "10月", "11月", "本周"])
    }
}
