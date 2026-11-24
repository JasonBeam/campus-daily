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
    let warm = SpendStatsText(theme:.warm, calendar:SchoolCalendar.shanghai)
    let clear = SpendStatsText(theme:.clear, calendar:SchoolCalendar.shanghai)

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

    // MARK: Category capsules

    func testACapsuleSaysItsAmountAndItsShareOnlyWhenCounted() {
        XCTAssertEqual(SpendStatsText.spokenShare(SpendShare(kind:.canteen, spent:Money(fen:8600), fraction:0.7)), "食堂，86 元，占 70%")
        let electricity = SpendShare(kind:.electricity, spent:Money(fen:4000), fraction:0, included:false)
        XCTAssertEqual(SpendStatsText.spokenShare(electricity), "电费，40 元")
        XCTAssertEqual(SpendStatsText.spokenShare(SpendShare(kind:.electricity, spent:Money(fen:4050), fraction:0.12)), "电费，40.50 元，占 12%")
        XCTAssertEqual(SpendStatsText.spokenShare(SpendShare(kind:.electricity, spent:.zero, fraction:0, included:false)), "电费，0 元")
        XCTAssertEqual(SpendStatsText.categoryValue(electricity), "不算")
        XCTAssertEqual(SpendStatsText.categoryValue(SpendShare(kind:.canteen, spent:Money(fen:8600), fraction:0.7)), "算进统计")
    }

    func testTheLastCapsuleCountedSaysItCantBeTurnedOff() {
        let canteen = SpendShare(kind:.canteen, spent:Money(fen:8600), fraction:1)
        let shower = SpendShare(kind:.shower, spent:Money(fen:2000), fraction:0, included:false)
        let electricity = SpendShare(kind:.electricity, spent:Money(fen:12000), fraction:0, included:false)
        XCTAssertTrue(SpendStatsText.isLastCounted(canteen, counted:[.canteen]))
        XCTAssertEqual(SpendStatsText.categoryHint(canteen, counted:[.canteen]), "至少要留一类，这一类拿不掉")
        XCTAssertEqual(SpendStatsText.categoryHint(shower, counted:[.canteen]), "轻点两下，加进或拿出统计")
        XCTAssertEqual(SpendStatsText.categoryHint(electricity, counted:[.canteen]), "轻点两下，加进或拿出统计")
        // 洗衣 is counted too, with nothing spent in the span (not listed): 食堂 can go.
        XCTAssertFalse(SpendStatsText.isLastCounted(canteen, counted:[.canteen, .laundry]))
        XCTAssertEqual(SpendStatsText.categoryHint(canteen, counted:[.canteen, .laundry]), "轻点两下，加进或拿出统计")
    }

    /// Spent only on categories left out: the chart's words, and what is read out.
    func testNothingCountedSpentButSomethingLeftOutWas() {
        var none = stats(total:0)
        none.shares = [SpendShare(kind:.canteen, spent:Money(fen:8600), fraction:0, included:false),
                       SpendShare(kind:.shower, spent:Money(fen:1200), fraction:0, included:false)]
        XCTAssertTrue(SpendStatsText.nothingCounted(none))
        XCTAssertEqual(warm.spokenTotal(none), "7 天花了 0 元。这段时间里，算进统计的分类都没花钱；点下面的分类加进来。")
        XCTAssertEqual(clear.spokenTotal(none), "合计 0 元。这段时间里，算进统计的分类都没花钱；点下面的分类加进来。")
        XCTAssertEqual(warm.spokenAmount(none), "7 天花了 0 元")
        var nothing = stats(total:0)
        nothing.shares = [SpendShare(kind:.electricity, spent:.zero, fraction:0, included:false)]
        XCTAssertFalse(SpendStatsText.nothingCounted(nothing), "nothing spent at all")
        XCTAssertEqual(clear.spokenTotal(nothing), "本期无支出")
        XCTAssertFalse(SpendStatsText.nothingCounted(stats()))
    }

    func testTheNewTotalReadOutAfterASwitch() {
        XCTAssertEqual(warm.spokenTotal(stats(total:38300)), "7 天花了 383 元")
        XCTAssertEqual(clear.spokenTotal(stats(total:38300)), "合计 383 元")
        XCTAssertEqual(warm.spokenTotal(stats(.month, total:38350)), "30 天花了 383.50 元")
        XCTAssertEqual(warm.spokenTotal(stats(total:0)), "这 7 天没用校园卡花钱。")
        XCTAssertEqual(SpendStatsText.categoryNote, "电费是整个宿舍一起交的，默认不算；点上面的分类可以加回来或拿掉。")
    }

    /// The capsules' dots go down the accent over those counted only; those left out get a ring.
    func testOnlyCountedCapsulesTakeAShade() {
        let shares = [SpendShare(kind:.canteen, spent:Money(fen:30000), fraction:0.8),
                      SpendShare(kind:.electricity, spent:Money(fen:12000), fraction:0, included:false),
                      SpendShare(kind:.shower, spent:Money(fen:6000), fraction:0.16),
                      SpendShare(kind:.other, spent:Money(fen:1500), fraction:0.04)]
        let shades = SpendShareFlow.shades(shares)
        XCTAssertNil(shades[.electricity])
        XCTAssertEqual(shades[.canteen], Theme.mark)
        XCTAssertEqual(shades[.shower], Theme.mark.opacity(0.62))
        XCTAssertEqual(shades[.other], Theme.ink3)
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

    func testDaysAreNamedInTheRecordsCalendar() {
        // The sample's calendar is the device's: east of 东八区 the same instant is a day later
        // in Shanghai's calendar, so naming it there would say 8月31日.
        var tokyo = Calendar(identifier:.gregorian)
        tokyo.timeZone = TimeZone(identifier:"Asia/Tokyo")!
        let start = tokyo.date(from:DateComponents(year:2026, month:9, day:1))!
        XCTAssertEqual(SpendStatsText(theme:.warm, calendar:SchoolCalendar.shanghai).termRange(start).text, "8月31日起 · ")
        XCTAssertEqual(SpendStatsText(theme:.warm, calendar:tokyo).termRange(start).text, "9月1日起 · ")
    }

    func testAWeekBarCanBeLookedAtOnceAnyOfItsDaysIsCovered() {
        let week = bar("20261005", fen:4200, days:["20261005", "20261006", "20261007", "20261008", "20261009", "20261010", "20261011"])
        XCTAssertTrue(SpendBarsChart.canLook(at:week, coveredFrom:"20261008"))
        XCTAssertTrue(SpendBarsChart.canLook(at:week, coveredFrom:"20261011"))
        XCTAssertFalse(SpendBarsChart.canLook(at:week, coveredFrom:"20261012"))
        XCTAssertTrue(SpendBarsChart.canLook(at:week, coveredFrom:nil))
        XCTAssertFalse(SpendBarsChart.canLook(at:bar("20261007", fen:0), coveredFrom:"20261008"))
        var before = bar("20260831", fen:0)
        before.beforeStart = true
        XCTAssertFalse(SpendBarsChart.canLook(at:before, coveredFrom:nil))
    }

    func testATouchLooksAtBarsOnlyOnceItMovesSideways() {
        typealias Chart = SpendBarsChart
        XCTAssertEqual(Chart.touch(.none, moved:.zero, at:10), .undecided)
        XCTAssertEqual(Chart.touch(.undecided, moved:CGSize(width:2, height:1), at:12), .undecided)
        XCTAssertEqual(Chart.touch(.undecided, moved:CGSize(width:5, height:2), at:15), .looking(x:15))
        XCTAssertEqual(Chart.touch(.undecided, moved:CGSize(width:2, height:6), at:12), .scrolling)
        // Decided stays decided, whichever way the finger goes after.
        XCTAssertEqual(Chart.touch(.looking(x:15), moved:CGSize(width:5, height:40), at:20), .looking(x:20))
        XCTAssertEqual(Chart.touch(.scrolling, moved:CGSize(width:80, height:6), at:90), .scrolling)
    }
}
