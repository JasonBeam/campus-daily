//
//  SampleDataTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/05.
//

import XCTest
import Core

/// The synthetic data the DEBUG demos and the sample mode share: the same values as the demos
/// had, never later than now, and the full 校园卡记录 sample pages like the school's.
final class SampleDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testHomeSnapshotHasTheDemoNumbers() {
        let s = SampleData.homeSnapshot(now: now)
        XCTAssertEqual(s.card.value, Money(yuanString: "86.50"))
        XCTAssertEqual(s.power.value?.remainingKWh, Decimal(string: "42.6"))
        XCTAssertEqual(s.power.value?.estimatedDaysLeft, Decimal(string: "9.26"))
        XCTAssertEqual(ClearBalanceText.number(s.power.value?.averageDailyKWh), "4.60")
        XCTAssertEqual(s.roomLabel, "3栋108")
        XCTAssertFalse(s.activity.value?.records.isEmpty ?? true)
    }

    func testNoRecordIsLaterThanAQuarterHourAgo() {
        let school = SampleData.calendar
        let home = SampleData.homeSnapshot(now: now).activity.value?.records ?? []
        let all = SampleData.cardRecords(days: SampleData.recordDays, now: now)
        for record in home + all {
            XCTAssertLessThanOrEqual(record.moment(calendar: school) ?? .distantFuture, now.addingTimeInterval(-15 * 60))
        }
    }

    func testRecordsAreNewestFirstWithVouchers() {
        let school = SampleData.calendar
        let rows = SampleData.cardRecords(days: SampleData.recordDays, now: now)
        XCTAssertGreaterThan(rows.count, 60)
        XCTAssertTrue(rows.allSatisfy { $0.voucher?.hasPrefix("99") == true })
        let moments = rows.compactMap { $0.moment(calendar: school) }
        XCTAssertEqual(moments, moments.sorted(by: >))
    }

    func testRecordPagesSplitTheRange() {
        let rows = SampleData.cardRecords(days: SampleData.recordDays, now: now)
        let begin = rows.map(\.date).min()!, end = rows.map(\.date).max()!
        let first = SampleData.recordPage(rows, CardHistoryQuery(begin: begin, end: end, page: 1, pageSize: 20))
        let past = SampleData.recordPage(rows, CardHistoryQuery(begin: begin, end: end, page: 99, pageSize: 20))
        XCTAssertEqual(first.total, rows.count)
        XCTAssertEqual(first.rows.count, 20)
        XCTAssertTrue(past.rows.isEmpty)
    }

    /// The records page's stats on the sample: every span has spending, a comparison for 7 and
    /// 30 days, no unsure day, and this term's weeks from its first day (an autumn term and a
    /// spring one nearly over).
    func testSampleRecordsGiveBelievableStats() throws {
        let school = SampleData.calendar
        for now in [now, Date(timeIntervalSince1970: 1_787_000_000)] {
            let rows = SampleData.cardRecords(days: SampleData.recordDays, now: now)
            let start = TermStart.defaultStart(today: now, calendar: school)
            var history = CardHistory(now: now, calendar: school)
            let first = SpendStats.firstDayNeeded(span: .term, today: now, termStart: start, calendar: school)
            let needed = min(first, SpendStats.firstDayNeeded(span: .month, today: now, termStart: start, calendar: school))
            while let q = history.nextQuery, !history.hasRead(through: needed) {
                history.receive(SampleData.recordPage(rows, q), for: q)
            }
            XCTAssertLessThanOrEqual(try XCTUnwrap(rows.map(\.date).min()), first, "the sample reaches back to the term's start")
            for span in SpendSpan.allCases {
                let stats = try XCTUnwrap(SpendStats.make(span: span, history: history, termStart: start, calendar: school), "\(span)")
                XCTAssertGreaterThan(stats.total, .zero, "\(span)")
                XCTAssertEqual(stats.unsureDays, 0, "\(span)")
                XCTAssertNil(stats.coveredFrom, "\(span)")
                XCTAssertEqual(stats.shares.first?.kind, .canteen, "\(span)")
                XCTAssertEqual(stats.shares.last?.kind, .other, "\(span)")
                XCTAssertFalse(stats.shares.contains { $0.kind == .topUp })
                if span == .term {
                    XCTAssertNil(stats.versusPrevious)
                    XCTAssertEqual(stats.termStart, SchoolCalendar.dayString(start, calendar: school))
                    XCTAssertEqual(stats.bars.last?.axisLabel, "本周")
                } else {
                    XCTAssertNotNil(stats.versusPrevious, "\(span)")
                    XCTAssertEqual(stats.bars.count, span == .week ? 7 : 30)
                }
            }
        }
    }

    func testAppActivitiesAreTheLastShowerAndLaundryOrder() {
        let items = SampleData.appActivities(now: now)
        XCTAssertEqual(items.map(\.id), ["demo-shower", "demo-laundry"])
        XCTAssertEqual(items.first?.amount, SampleData.lastShowerCost)
    }

    func testWasherIsFreeWithFourPrograms() {
        let washer = SampleData.washerSnapshot(status: 0)
        XCTAssertEqual(washer.info.deviceNo, "3")
        XCTAssertEqual(washer.info.programs.count, 4)
        XCTAssertTrue(washer.scan.createOrderEnabled)
        XCTAssertFalse(SampleData.washerSnapshot(status: 1).scan.createOrderEnabled)
    }

    func testShowerRecordsByName() {
        XCTAssertEqual(SampleData.showerRecord("sh-done", now: now)?.phase, .done)
        XCTAssertEqual(SampleData.showerRecord("sh-run", now: now)?.phase, .running)
        XCTAssertNil(SampleData.showerRecord("nothing", now: now))
    }
}
