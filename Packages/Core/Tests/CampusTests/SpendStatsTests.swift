//
//  SpendStatsTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
@testable import Core

/// The records page's spending stats: spans counting today, the average over the days covered,
/// the period before, day and week bars with their labels, unsure days and the categories.
final class SpendStatsTests: XCTestCase {
    let cal = SchoolCalendar.shanghai
    /// Tuesday 2026-11-24 12:00 in Shanghai.
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))! }
    var autumn: Date { day(2026, 9, 1) }

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    var vouchers = 0
    func record(_ date: String, _ yuan: String, _ title: String = "POS消费示例面馆", time: String = "120000",
                flag: String? = "1", voucher: Bool = true) -> CardRecord {
        vouchers += 1
        return CardRecord(date: date, time: time, title: title, amount: Money(yuanString: yuan)!, balanceAfter: nil,
                          direction: flag, voucher: voucher ? String(format: "99%018d", vouchers) : nil)
    }

    /// The school's pages over `rows` (newest first), read back from `now` until `through`
    /// (`yyyyMMdd`) is held, or to the end when nil.
    func history(_ rows: [CardRecord], through: String?, now: Date? = nil) -> CardHistory {
        let rows = rows.sorted { ($0.date, $0.time) > ($1.date, $1.time) }
        var h = CardHistory(now: now ?? noon)
        while let q = h.nextQuery {
            if let through, h.hasRead(through: through) { break }
            h.receive(SampleData.recordPage(rows, q), for: q)
        }
        return h
    }

    /// The stats with the records read back as the records page reads them for `span`, or to the
    /// list's end.
    func stats(_ span: SpendSpan, _ rows: [CardRecord], toEnd: Bool = false, termStart: Date? = nil) -> SpendStats? {
        let start = termStart ?? autumn
        let through = toEnd ? nil : SpendStats.firstDayNeeded(span: span, today: noon, termStart: start, calendar: cal)
        return SpendStats.make(span: span, history: history(rows, through: through), termStart: start, calendar: cal)
    }

    // MARK: Spans

    func testSevenDaysCountTodayAndLeaveMoneyInOut() throws {
        let rows = [
            record("20261124", "12.00"),
            record("20261124", "50.00", "校园卡充值", flag: nil),
            record("20261124", "3.00", "退款", flag: "2"),
            record("20261123", "1.10", "蓝牙热水"),
            record("20261118", "5.00"),
            record("20261117", "7.00"),
        ]
        let s = try XCTUnwrap(stats(.week, rows))
        XCTAssertEqual(s.span, .week)
        XCTAssertEqual(s.total, Money(fen: 1810))
        XCTAssertEqual(s.dailyAverage, Money(fen: 259), "18.10 ÷ 7, rounded")
        XCTAssertEqual(s.versusPrevious, Money(fen: 1110), "18.10 − 7.00")
        XCTAssertEqual(s.bars.map(\.id), ["20261118", "20261119", "20261120", "20261121", "20261122", "20261123", "20261124"])
        XCTAssertEqual(s.bars.map(\.axisLabel), ["三", "四", "五", "六", "日", "一", "今天"])
        XCTAssertEqual(s.bars.map(\.spent.fen), [500, 0, 0, 0, 0, 110, 1200])
        XCTAssertEqual(s.bars.map(\.isCurrent), [false, false, false, false, false, false, true])
        XCTAssertTrue(s.bars.allSatisfy { !$0.unsure && !$0.beforeStart && $0.days == [$0.id] })
        XCTAssertEqual(s.unsureDays, 0)
        XCTAssertNil(s.coveredFrom)
        XCTAssertNil(s.termStart)
        XCTAssertFalse(s.isEmpty)
    }

    func testThirtyDaysAcrossMonthsLabelFirstMiddleAndToday() throws {
        let rows = [record("20261124", "10.00"), record("20261026", "20.00"), record("20261025", "4.00"), record("20260926", "6.00")]
        let s = try XCTUnwrap(stats(.month, rows))
        XCTAssertEqual(s.bars.count, 30)
        XCTAssertEqual(s.bars.first?.id, "20261026")
        XCTAssertEqual(s.bars.last?.id, "20261124")
        let labelled = s.bars.enumerated().compactMap { i, bar in bar.axisLabel.map { (i, $0) } }
        XCTAssertEqual(labelled.map(\.0), [0, 15, 29])
        XCTAssertEqual(labelled.map(\.1), ["10月26日", "11月10日", "今天"])
        XCTAssertEqual(s.total, Money(fen: 3000))
        XCTAssertEqual(s.dailyAverage, Money(fen: 100))
        XCTAssertEqual(s.versusPrevious, Money(fen: 2000), "30.00 − (4.00 + 6.00) of 9月26日…10月25日")
    }

    func testTodayCountsAsADayWhileItIsNotOver() throws {
        let rows = (0..<7).map { record(String(format: "202611%02d", 18 + $0), "7.00") }
        let s = try XCTUnwrap(stats(.week, rows))
        XCTAssertEqual(s.total, Money(fen: 4900))
        XCTAssertEqual(s.dailyAverage, Money(fen: 700))
        XCTAssertEqual(s.bars.last?.isCurrent, true)
        XCTAssertEqual(s.bars.filter(\.isCurrent).count, 1)
    }

    func testNotReadYetIsNil() {
        // Only today's range (14 days) is read: 7 days can be told, 30 cannot.
        let rows = [record("20261124", "1.00"), record("20261001", "1.00")]
        let h = history(rows, through: "20261111")
        XCTAssertNotNil(SpendStats.make(span: .week, history: h, termStart: autumn, calendar: cal))
        XCTAssertNil(SpendStats.make(span: .month, history: h, termStart: autumn, calendar: cal))
        XCTAssertNil(SpendStats.make(span: .term, history: h, termStart: autumn, calendar: cal))
    }

    func testFirstDayNeeded() {
        XCTAssertEqual(SpendStats.firstDayNeeded(span: .week, today: noon, termStart: autumn, calendar: cal), "20261111")
        XCTAssertEqual(SpendStats.firstDayNeeded(span: .month, today: noon, termStart: autumn, calendar: cal), "20260926")
        XCTAssertEqual(SpendStats.firstDayNeeded(span: .term, today: noon, termStart: autumn, calendar: cal), "20260901")
        XCTAssertEqual(SpendStats.firstDayNeeded(span: .term, today: noon, termStart: day(2026, 12, 1), calendar: cal), "20261124",
                       "a start after today is today")
    }

    func testAWeChatMealCountsOnceAndItsHalfNever() throws {
        var half = record("20261124", "16.00", "微信支付(手机)", flag: "2")
        var meal = record("20261124", "16.00", "POS消费示例盖饭")
        half.voucher = "99000000000000000777"; meal.voucher = half.voucher
        let s = try XCTUnwrap(stats(.week, [half, meal]))
        XCTAssertEqual(s.total, Money(fen: 1600))
        XCTAssertEqual(s.shares.map(\.kind), [.canteen])
    }

    /// A payment from the card under a top-up's name (「网费充值」, 「xx圈存」 with direction 「1」)
    /// is spent like any other, as in the list's 「花了」: under 其他.
    func testAPaymentUnderATopUpsNameCountsAsOther() throws {
        let rows = [record("20261124", "12.00"), record("20261124", "30.00", "网费充值", time: "130000"),
                    record("20261124", "50.00", "校园卡充值", time: "140000", flag: nil),
                    record("20261123", "20.00", "示例圈存"), record("20261120", "5.00", "蓝牙热水")]
        let s = try XCTUnwrap(stats(.week, rows))
        XCTAssertEqual(s.total, Money(fen: 6700))
        XCTAssertEqual(s.bars.last?.spent, Money(fen: 4200))
        XCTAssertEqual(s.shares.map(\.kind), [.canteen, .shower, .other])
        XCTAssertEqual(s.shares.map(\.spent.fen), [1200, 500, 5000])
    }

    /// Each day's bar is the list's 「花了」 for that day (`CardDays`), whatever its records.
    func testEachDaysBarIsTheListsDayTotal() throws {
        let rows = [record("20261124", "12.00"), record("20261124", "30.00", "网费充值", time: "130000"),
                    record("20261124", "50.00", "校园卡充值", time: "140000", flag: nil),
                    record("20261124", "3.00", "退款", time: "150000", flag: "2"),
                    record("20261123", "20.00", "示例圈存"), record("20261123", "8.80", "电费", time: "090000"),
                    record("20261121", "4.00", "洗衣"), record("20261118", "16.00", "示例便利店"),
                    record("20261112", "7.00")]
        let through = SpendStats.firstDayNeeded(span: .week, today: noon, termStart: autumn, calendar: cal)
        let h = history(rows, through: through)
        let s = try XCTUnwrap(SpendStats.make(span: .week, history: h, termStart: autumn, calendar: cal))
        let days = CardDays.groups(history: h, app: [], now: noon, calendar: cal)
        XCTAssertEqual(days.first { $0.id == "20261124" }?.total, Money(fen: 4200))
        for bar in s.bars {
            XCTAssertEqual(bar.spent, days.first { $0.id == bar.id }?.total ?? .zero, bar.id)
        }
        XCTAssertEqual(s.bars.map(\.spent.fen), [1600, 0, 0, 400, 0, 2880, 4200])
    }

    // MARK: Unsure days

    func testARecordThatMayRepeatMakesItsDayUnsureAndTheComparisonGoes() throws {
        let rows = [record("20261124", "5.00"), record("20261122", "3.00", voucher: false), record("20261115", "4.00", voucher: false)]
        let s = try XCTUnwrap(stats(.week, rows))
        XCTAssertEqual(s.unsureDays, 1)
        XCTAssertEqual(s.bars.filter(\.unsure).map(\.id), ["20261122"])
        XCTAssertEqual(s.total, Money(fen: 800), "what was read still counts")
        XCTAssertNil(s.versusPrevious, "11月15日 in the period before is unsure")
    }

    func testOneUnsureDayBeforeSevenCertainDaysDropsOnlyTheComparison() throws {
        let rows = [record("20261124", "6.00"), record("20261120", "8.00"), record("20261118", "7.00"),
                    record("20261116", "5.00"), record("20261114", "4.00", voucher: false), record("20261111", "3.00")]
        let s = try XCTUnwrap(stats(.week, rows))
        XCTAssertNil(s.versusPrevious, "11月14日 in the 7 days before may repeat a record")
        XCTAssertEqual(s.total, Money(fen: 2100))
        XCTAssertEqual(s.dailyAverage, Money(fen: 300))
        XCTAssertEqual(s.bars.map(\.spent.fen), [700, 0, 800, 0, 0, 0, 600])
        XCTAssertEqual(s.bars.map(\.axisLabel), ["三", "四", "五", "六", "日", "一", "今天"])
        XCTAssertTrue(s.bars.allSatisfy { !$0.unsure })
        XCTAssertEqual(s.unsureDays, 0)
        XCTAssertNil(s.coveredFrom)
        XCTAssertEqual(s.shares.map(\.kind), [.canteen])
    }

    func testOneUnsureDayBeforeThirtyCertainDaysDropsOnlyTheComparison() throws {
        let rows = [record("20261124", "10.00"), record("20261101", "20.00"), record("20261026", "30.00"),
                    record("20261020", "9.00"), record("20261010", "4.00", voucher: false), record("20260926", "2.00")]
        let s = try XCTUnwrap(stats(.month, rows))
        XCTAssertNil(s.versusPrevious, "10月10日 in the 30 days before may repeat a record")
        XCTAssertEqual(s.total, Money(fen: 6000))
        XCTAssertEqual(s.dailyAverage, Money(fen: 200))
        XCTAssertEqual(s.bars.count, 30)
        XCTAssertEqual(s.bars.first?.spent, Money(fen: 3000))
        XCTAssertEqual(s.bars.first { $0.id == "20261101" }?.spent, Money(fen: 2000))
        XCTAssertEqual(s.bars.last?.spent, Money(fen: 1000))
        XCTAssertTrue(s.bars.allSatisfy { !$0.unsure })
        XCTAssertEqual(s.unsureDays, 0)
        XCTAssertNil(s.coveredFrom)
    }

    func testARecordInOrOutIsLeftOutAndItsDayUnsure() throws {
        let rows = [record("20261124", "5.00"), record("20261123", "-2.00", "示例", flag: nil)]
        let s = try XCTUnwrap(stats(.week, rows))
        XCTAssertEqual(s.total, Money(fen: 500))
        XCTAssertEqual(s.unsureDays, 1)
        XCTAssertEqual(s.bars.first { $0.id == "20261123" }?.unsure, true)
        XCTAssertNotNil(s.versusPrevious, "only the period before decides the comparison")
    }

    func testARecordWithoutATimeMakesItsDayUnsure() throws {
        let rows = [record("20261124", "5.00"), record("20261121", "2.00", time: "99xx")]
        let s = try XCTUnwrap(stats(.week, rows))
        XCTAssertEqual(s.total, Money(fen: 500))
        XCTAssertEqual(s.bars.filter(\.unsure).map(\.id), ["20261121"])
    }

    func testDaysTheSchoolStoppedPagingAreUnsure() throws {
        // Today's range says 60 records but every page brings the same 50: it is left there,
        // and its days from the oldest read are unsure.
        let fifty = (0..<50).map { i in record("20261124", "1.00", time: String(format: "%06d", 235900 - i * 100)) }
        var h = CardHistory(now: noon)
        while let q = h.nextQuery, !h.hasRead(through: "20261111") {
            h.receive(q.page > 0 && q.end == "20261124" ? CardRecordPage(total: 60, rows: fifty) : CardRecordPage(total: 0, rows: []), for: q)
        }
        let s = try XCTUnwrap(SpendStats.make(span: .week, history: h, termStart: autumn, calendar: cal))
        XCTAssertEqual(s.unsureDays, 7)
        XCTAssertNil(s.versusPrevious)
    }

    // MARK: Where the records begin

    func testRecordsBeginningInsideTheSpanAreCoveredFromThatDay() throws {
        let rows = [record("20261124", "6.00"), record("20261121", "6.00")]
        let s = try XCTUnwrap(stats(.week, rows, toEnd: true))
        XCTAssertEqual(s.coveredFrom, "20261121")
        XCTAssertEqual(s.total, Money(fen: 1200))
        XCTAssertEqual(s.dailyAverage, Money(fen: 300), "12.00 over the 4 days from 11月21日")
        XCTAssertNil(s.versusPrevious)
        XCTAssertEqual(s.bars.count, 7)
        XCTAssertEqual(s.unsureDays, 0, "days before the records are not unsure")
    }

    func testRecordsBeginningInsideThePeriodBeforeHaveNoComparison() throws {
        let rows = [record("20261124", "6.00"), record("20261116", "6.00")]
        let s = try XCTUnwrap(stats(.week, rows, toEnd: true))
        XCTAssertNil(s.coveredFrom)
        XCTAssertNil(s.versusPrevious, "the school may hold nothing before 11月16日")
        XCTAssertEqual(s.dailyAverage, Money(fen: 86))
    }

    func testTheEndOfTheListWithRecordsBeforeBothPeriodsCompares() throws {
        let rows = [record("20261124", "6.00"), record("20261001", "6.00")]
        let s = try XCTUnwrap(stats(.week, rows, toEnd: true))
        XCTAssertNil(s.coveredFrom)
        XCTAssertEqual(s.versusPrevious, Money(fen: 600))
    }

    // MARK: This term

    func testTermBarsAreMondayWeeksFromTheStartDay() throws {
        let rows = [record("20260901", "10.00"), record("20260831", "99.00"), record("20260907", "4.00"),
                    record("20261005", "3.00"), record("20261124", "2.00"), record("20261123", "1.00")]
        let s = try XCTUnwrap(stats(.term, rows))
        XCTAssertEqual(s.termStart, "20260901")
        XCTAssertNil(s.versusPrevious)
        XCTAssertEqual(s.bars.count, 13)
        XCTAssertEqual(s.bars[0].id, "20260901")
        XCTAssertEqual(s.bars[0].days, ["20260901", "20260902", "20260903", "20260904", "20260905", "20260906"],
                       "Monday 8月31日 is before the start: not counted")
        XCTAssertEqual(s.bars[0].spent, Money(fen: 1000))
        XCTAssertEqual(s.bars[1].id, "20260907")
        XCTAssertEqual(s.bars[1].days.count, 7)
        XCTAssertEqual(s.bars.last?.days, ["20261123", "20261124"])
        XCTAssertEqual(s.bars.last?.spent, Money(fen: 300))
        XCTAssertEqual(s.bars.map(\.isCurrent), Array(repeating: false, count: 12) + [true])
        XCTAssertTrue(s.bars.allSatisfy { !$0.beforeStart })
        let labelled = s.bars.enumerated().compactMap { i, bar in bar.axisLabel.map { "\(i):\($0)" } }
        XCTAssertEqual(labelled, ["0:9月", "5:10月", "9:11月", "12:本周"])
        XCTAssertEqual(s.total, Money(fen: 2000))
        XCTAssertEqual(s.dailyAverage, Money(fen: 24), "20.00 over 85 days, 9月1日 through today")
    }

    func testATermStartedThisWeekHasOneBar() throws {
        let s = try XCTUnwrap(stats(.term, [record("20261124", "3.00")], termStart: day(2026, 11, 23)))
        XCTAssertEqual(s.bars.count, 1)
        XCTAssertEqual(s.bars[0].days, ["20261123", "20261124"])
        XCTAssertEqual(s.bars[0].axisLabel, "本周")
        XCTAssertEqual(s.termStart, "20261123")
    }

    func testAnUnsureDayMakesItsWeekUnsure() throws {
        let s = try XCTUnwrap(stats(.term, [record("20261110", "3.00", voucher: false), record("20261124", "1.00")]))
        XCTAssertEqual(s.bars.filter(\.unsure).map(\.id), ["20261109"])
        XCTAssertEqual(s.unsureDays, 1)
    }

    // MARK: Categories

    func testSharesBiggestFirstWithOtherLast() throws {
        let rows = [record("20261124", "30.00"), record("20261124", "50.00", "示例便利店", time: "130000"),
                    record("20261123", "10.00", "蓝牙热水"), record("20261122", "20.00", "电费"),
                    record("20261121", "10.00", "洗衣")]
        let s = try XCTUnwrap(stats(.week, rows))
        XCTAssertEqual(s.shares.map(\.kind), [.canteen, .electricity, .shower, .laundry, .other],
                       "a tie keeps the categories' own order")
        XCTAssertEqual(s.shares.map(\.spent.fen), [3000, 2000, 1000, 1000, 5000])
        XCTAssertEqual(s.shares.map(\.fraction).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(s.shares[0].fraction, 0.25, accuracy: 1e-9)
        XCTAssertFalse(s.shares.contains { $0.kind == .topUp })
    }

    func testSharesOnlyCountTheSpan() throws {
        let s = try XCTUnwrap(stats(.week, [record("20261124", "3.00"), record("20261110", "8.00", "电费")]))
        XCTAssertEqual(s.shares.map(\.kind), [.canteen])
        XCTAssertEqual(s.shares[0].fraction, 1)
    }

    func testNothingSpentIsEmpty() throws {
        let rows = [record("20261124", "50.00", "校园卡充值", flag: nil)]
        let s = try XCTUnwrap(stats(.month, rows))
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.total, .zero)
        XCTAssertEqual(s.dailyAverage, .zero)
        XCTAssertEqual(s.versusPrevious, .zero)
        XCTAssertTrue(s.shares.isEmpty)
        XCTAssertTrue(s.bars.allSatisfy { $0.spent == .zero })
    }

    func testAverageRoundsToTheNearestFen() {
        XCTAssertEqual(SpendStats.dividedRounding(1810, by: 7), 259)
        XCTAssertEqual(SpendStats.dividedRounding(10, by: 4), 3, "2.5 fen rounds up")
        XCTAssertEqual(SpendStats.dividedRounding(-10, by: 4), -3)
        XCTAssertEqual(SpendStats.dividedRounding(0, by: 30), 0)
    }

    func testSpanStoreKeyAndDays() {
        XCTAssertEqual(SpendSpan.storeKey, "records.statsSpan")
        XCTAssertEqual(SpendSpan.week.days, 7)
        XCTAssertEqual(SpendSpan.month.days, 30)
        XCTAssertNil(SpendSpan.term.days)
    }
}
