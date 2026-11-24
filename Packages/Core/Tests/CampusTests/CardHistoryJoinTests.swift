//
//  CardHistoryJoinTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
@testable import Core

/// A read from today joined onto an earlier read kept in memory (only the newest range read
/// again), and home's last records shown until the read's own pages come, never twice.
final class CardHistoryJoinTests: XCTestCase {
    let cal = SchoolCalendar.shanghai
    /// Tuesday 2026-11-24 12:00 in Shanghai.
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))! }
    func noon(back days: Int) -> Date { cal.date(byAdding: .day, value: -days, to: noon)! }
    func id(back days: Int, from now: Date? = nil) -> String {
        SchoolCalendar.dayString(cal.date(byAdding: .day, value: -days, to: now ?? noon)!, calendar: cal)
    }

    var vouchers = 0
    func record(_ date: String, _ yuan: String = "10.00", time: String = "120000", voucher: Bool = true) -> CardRecord {
        vouchers += 1
        return CardRecord(date: date, time: time, title: "POS消费示例面馆", amount: Money(yuanString: yuan)!, balanceAfter: nil,
                          direction: "1", voucher: voucher ? String(format: "99%018d", vouchers) : nil)
    }

    /// One record a day at noon, `days` back from `now`'s day.
    func daily(_ days: Range<Int>, now: Date? = nil) -> [CardRecord] {
        days.map { record(id(back: $0, from: now)) }
    }

    func sorted(_ rows: [CardRecord]) -> [CardRecord] { rows.sorted { ($0.date, $0.time) > ($1.date, $1.time) } }

    /// Reads `rows` from `now` until `done` says stop (or the end); the pages asked for are counted.
    func read(_ rows: [CardRecord], now: Date, from start: CardHistory? = nil, pages: inout Int,
              until done: (CardHistory) -> Bool) -> CardHistory {
        let rows = sorted(rows)
        var h = start ?? CardHistory(now: now)
        while let q = h.nextQuery, !done(h) {
            pages += 1
            h.receive(SampleData.recordPage(rows, q), for: q)
        }
        return h
    }

    func read(_ rows: [CardRecord], now: Date, through day: String) -> CardHistory {
        var pages = 0
        return read(rows, now: now, pages: &pages) { $0.hasRead(through: day) }
    }

    func firstRange(_ rows: [CardRecord], now: Date) -> CardHistory {
        var pages = 0
        return read(rows, now: now, pages: &pages) { $0.holdsFirstRange }
    }

    // MARK: Joining

    func testTheNewestRangeJoinsAnEarlierReadOfTheSameDay() throws {
        let rows = daily(0..<70)
        let earlier = read(rows, now: noon, through: id(back: 59))
        XCTAssertEqual(earlier.readThrough, id(back: 69))

        // Since then: a new record today; and an old record the school no longer lists (were the
        // older days read again, it would go).
        let today = record(id(back: 0), "3.00", time: "150000")
        let now = rows.filter { $0.date != id(back: 40) } + [today]
        let fresh = firstRange(now, now: noon)
        let joined = try XCTUnwrap(fresh.joined(earlier: earlier))

        XCTAssertTrue(joined.hasRead(through: id(back: 69)))
        XCTAssertFalse(joined.hasRead(through: id(back: 70)))
        XCTAssertEqual(joined.records.count, 71)
        XCTAssertEqual(joined.records.filter { $0.date == id(back: 0) }.count, 2)
        XCTAssertEqual(joined.records.filter { $0.date == id(back: 40) }.count, 1, "older days are the earlier read's")
        XCTAssertEqual(joined.records.map(\.date), joined.records.map(\.date).sorted(by: >))
        XCTAssertEqual(joined.nextQuery?.end, id(back: 70), "on back from where the earlier read was")
        XCTAssertEqual(joined.nextQuery?.begin, id(back: 83))
        XCTAssertTrue(joined.isComplete(day: id(back: 30)))
    }

    /// Read yesterday, joined today: yesterday's late record and today's come once each, and
    /// the stats work as on a read from today.
    func testAnEarlierReadOfYesterdayJoinsAndItsLastDayIsReadAgain() throws {
        let yesterday = noon(back: 1)
        let rows = daily(0..<40, now: yesterday)
        let earlier = read(rows, now: yesterday, through: id(back: 29, from: yesterday))

        let late = record(id(back: 1), "4.00", time: "200000")
        let today = record(id(back: 0), "5.00")
        let fresh = firstRange(rows + [late, today], now: noon)
        let joined = try XCTUnwrap(fresh.joined(earlier: earlier))

        XCTAssertEqual(joined.records.count, rows.count + 2)
        XCTAssertEqual(joined.records.filter { $0.date == id(back: 1) }.count, 2)
        XCTAssertTrue(joined.hasRead(through: id(back: 42)), "where yesterday's read was: 41 days before yesterday")
        XCTAssertEqual(joined.nextQuery?.end, id(back: 43))

        let all = read(rows + [late, today], now: noon, through: id(back: 41))
        let stats = try XCTUnwrap(SpendStats.make(span: .month, history: joined, termStart: noon, calendar: cal))
        XCTAssertEqual(stats, SpendStats.make(span: .month, history: all, termStart: noon, calendar: cal),
                       "the same stats as reading it all again")
    }

    /// The earlier read's today is no longer among the days read again (two weeks on), or it
    /// holds no range older than the newest: nothing to join.
    func testNothingJoinsWhenTheEarlierReadIsTooOldOrTooShort() {
        let rows = daily(0..<60)
        let twoWeeksAgo = noon(back: 14)
        let old = read(rows, now: twoWeeksAgo, through: id(back: 40, from: twoWeeksAgo))
        let fresh = firstRange(rows, now: noon)
        XCTAssertNil(fresh.joined(earlier: old))

        let thirteenDaysAgo = noon(back: 13)
        let recent = read(rows, now: thirteenDaysAgo, through: id(back: 40, from: thirteenDaysAgo))
        XCTAssertNotNil(fresh.joined(earlier: recent))

        let short = firstRange(rows, now: noon)
        XCTAssertNil(fresh.joined(earlier: short), "only the newest range: nothing older to add")
        XCTAssertNil(CardHistory(now: noon).joined(earlier: recent), "the newest range not read yet")
    }

    /// The earlier read's unsure days and its end come along.
    func testUnsureDaysAndTheEndComeAlong() throws {
        var rows = daily(0..<20)
        rows.append(record(id(back: 16), voucher: false))
        let earlier = read(rows, now: noon, through: "00000000")
        XCTAssertTrue(earlier.reachedEnd)
        XCTAssertFalse(earlier.isComplete(day: id(back: 16)))

        let joined = try XCTUnwrap(firstRange(rows, now: noon).joined(earlier: earlier))
        XCTAssertTrue(joined.reachedEnd)
        XCTAssertNil(joined.nextQuery)
        XCTAssertFalse(joined.isComplete(day: id(back: 16)), "may repeat: no total")
        XCTAssertTrue(joined.isComplete(day: id(back: 15)))
        XCTAssertEqual(joined.records.count, rows.count)
    }

    // MARK: Home's records first

    func activity(_ rows: [CardRecord], complete: Bool = true, end: String? = nil) -> CardActivity {
        CardActivity(records: sorted(rows).map { var r = $0; r.voucher = nil; return r },
                     begin: id(back: 6), end: end ?? id(back: 0), complete: complete)
    }

    func testHomesRecordsShowBeforeTheFirstPageButNeverCountForTheStats() {
        let home = daily(0..<7)
        var h = CardHistory(now: noon)
        h.prefill(activity(home))
        XCTAssertEqual(h.records.count, 7)
        XCTAssertEqual(h.readThrough, id(back: 6))
        XCTAssertTrue(h.isComplete(day: id(back: 1)), "a day home read in full has its total")
        XCTAssertFalse(h.isComplete(day: id(back: 0)), "home read today some time ago")
        XCTAssertFalse(h.isComplete(day: id(back: 7)))
        XCTAssertFalse(h.hasRead(through: id(back: 0)))
        XCTAssertNil(SpendStats.make(span: .week, history: h, termStart: noon, calendar: cal))
        XCTAssertEqual(h.nextQuery?.page, 1, "the read starts as usual")
        let days = CardDays.groups(history: h, app: [], now: noon, calendar: cal)
        XCTAssertEqual(days.map(\.id), (0..<7).map { id(back: $0) })
        XCTAssertNil(days[0].total)
        XCTAssertEqual(days[1].total, Money(fen: 1000))
    }

    /// The first page cuts yesterday: today and yesterday are the read's own, the days before
    /// still home's, and nothing shows twice. Once the range is read, only the read's records are left.
    func testThePagesTakeOverDayByDayWithoutCountingTwice() {
        let today = (0..<30).map { record(id(back: 0), "1.00", time: String(format: "08%02d00", $0)) }
        let yesterday = (0..<30).map { record(id(back: 1), "1.00", time: String(format: "08%02d00", $0)) }
        let older = daily(2..<14)
        let school = sorted(today + yesterday + older)
        var h = CardHistory(now: noon)
        h.prefill(activity(today + yesterday + daily(2..<7)))

        var q = h.nextQuery!
        h.receive(SampleData.recordPage(school, q), for: q)
        XCTAssertEqual(h.records.filter { $0.date == id(back: 0) }.count, 30)
        XCTAssertEqual(h.records.filter { $0.date == id(back: 1) }.count, 20, "the read's part of the cut day; home's of it go")
        XCTAssertEqual(h.records.filter { $0.date == id(back: 2) }.count, 1, "home's")
        XCTAssertFalse(h.isComplete(day: id(back: 1)))
        XCTAssertTrue(h.isComplete(day: id(back: 2)))
        XCTAssertEqual(h.records.count, 30 + 20 + 5)

        q = h.nextQuery!
        h.receive(SampleData.recordPage(school, q), for: q)
        XCTAssertTrue(h.holdsFirstRange)
        XCTAssertEqual(h.records.count, school.count)
        XCTAssertTrue(h.records.allSatisfy { $0.voucher != nil }, "home's records are all gone")
        XCTAssertNotNil(SpendStats.make(span: .week, history: h, termStart: noon, calendar: cal))
    }

    /// A home read cut short holds the days after its oldest; one of another day is not used.
    func testOnlyDaysHomeHoldsInFullAndOnlyTodaysRead() {
        var h = CardHistory(now: noon)
        h.prefill(activity(daily(0..<5), complete: false))
        XCTAssertEqual(h.readThrough, id(back: 3))
        XCTAssertEqual(h.records.count, 4)

        var stale = CardHistory(now: noon)
        stale.prefill(activity(daily(1..<7), end: id(back: 1)))
        XCTAssertTrue(stale.records.isEmpty)
        XCTAssertNil(stale.readThrough)

        var started = firstRange(daily(0..<20), now: noon)
        let before = started
        started.prefill(activity(daily(0..<7)))
        XCTAssertEqual(started, before, "only before the read has a page")
    }
}
