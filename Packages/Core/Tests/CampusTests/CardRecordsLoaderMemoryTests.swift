//
//  CardRecordsLoaderMemoryTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
@testable import Core

/// 校园卡记录 opened again in the same launch: the records kept in memory show at once, only the
/// newest range is read again and joined on, and home's last records fill a first visit's list
/// until its pages come.
@MainActor final class CardRecordsLoaderMemoryTests: XCTestCase {
    let cal = SchoolCalendar.shanghai
    /// Tuesday 2026-11-24 12:00 in Shanghai.
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))! }
    func id(back days: Int, from now: Date? = nil) -> String {
        SchoolCalendar.dayString(cal.date(byAdding: .day, value: -days, to: now ?? noon)!, calendar: cal)
    }

    /// The school's records, paged; every page asked for is counted, and today's range can be held
    /// or made to fail.
    actor School {
        var rows: [CardRecord]
        var queries: [CardHistoryQuery] = []
        var person = 1
        var holdNewest = false
        var failNewest = false
        var waiting: [CheckedContinuation<Void, Never>] = []
        let today: String

        init(rows: [CardRecord], today: String) { self.rows = rows; self.today = today }

        func set(rows: [CardRecord]) { self.rows = rows }
        func add(_ row: CardRecord) { rows.append(row) }
        func hold() { holdNewest = true }
        func release() { holdNewest = false; for c in waiting { c.resume() }; waiting = [] }
        func fail(_ on: Bool) { failNewest = on }
        func clear() { queries = [] }
        var isWaiting: Bool { !waiting.isEmpty }

        func page(_ query: CardHistoryQuery) async throws -> CardRecordPage {
            queries.append(query)
            if query.end == today {
                if holdNewest { await withCheckedContinuation { waiting.append($0) } }
                if failNewest { throw ServiceError.offline }
            }
            let sorted = rows.sorted { ($0.date, $0.time) > ($1.date, $1.time) }
            return SampleData.recordPage(sorted, query)
        }
    }

    var vouchers = 0
    func record(_ date: String, _ yuan: String = "10.00", time: String = "120000") -> CardRecord {
        vouchers += 1
        return CardRecord(date: date, time: time, title: "POS消费示例面馆", amount: Money(yuanString: yuan)!, balanceAfter: nil,
                          direction: "1", voucher: String(format: "99%018d", vouchers))
    }

    func loader(_ school: School, memory: CardRecordsMemory?, now: Date? = nil, stamp: Int = 1,
                prefill: CardActivity? = nil) -> CardRecordsLoader {
        var fill: (@MainActor @Sendable () -> CardActivity?)?
        if let prefill { fill = { prefill } }
        let source = CardRecordsSource(stamp: { stamp }, page: { query, _ in try await school.page(query) },
                                       memory: memory, prefill: fill)
        return CardRecordsLoader(source: source, now: { [noon] in now ?? noon })
    }

    /// No read running for a few turns in a row (an older read starts in a task of its own).
    func settled(_ loader: CardRecordsLoader, file: StaticString = #filePath, line: UInt = #line) async {
        var quiet = 0
        for _ in 0..<2000 {
            quiet = !loader.state.reloading && !loader.state.loadingMore ? quiet + 1 : 0
            if quiet >= 5 { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("the reads never settled", file: file, line: line)
    }

    func held(_ school: School, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 {
            if await school.isWaiting { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("today's range was never asked for", file: file, line: line)
    }

    /// A 30-day visit read back 60 days, kept.
    func firstVisit(_ school: School, memory: CardRecordsMemory) async -> CardHistory? {
        let first = loader(school, memory: memory)
        first.setTarget(id(back: 59))
        await first.reload()
        await settled(first)
        return first.state.history
    }

    func testOpenedAgainOnlyTheNewestRangeIsReadAndJoined() async throws {
        let rows = (0..<90).map { record(id(back: $0)) }
        let school = School(rows: rows, today: id(back: 0))
        let memory = CardRecordsMemory()
        let visited = await firstVisit(school, memory: memory)
        let kept = try XCTUnwrap(visited)
        XCTAssertTrue(kept.hasRead(through: id(back: 59)))
        XCTAssertEqual(memory.history(for: 1), kept)
        await school.clear()

        // Since: a new record today; and one 40 days back the school no longer lists.
        let today = record(id(back: 0), "3.00", time: "150000")
        await school.set(rows: rows.filter { $0.date != id(back: 40) } + [today])
        await school.hold()
        let again = loader(school, memory: memory)
        again.setTarget(id(back: 59))
        let visit = Task { await again.reload() }
        await held(school)
        XCTAssertEqual(again.state.phase, .loaded, "the kept records show at once")
        XCTAssertEqual(again.state.history, kept)
        XCTAssertTrue(again.state.reloading)

        await school.release()
        await visit.value
        await settled(again)
        let queries = await school.queries
        XCTAssertEqual(queries.map(\.begin), [id(back: 13)], "one page: the newest range only")
        let joined = try XCTUnwrap(again.state.history)
        XCTAssertEqual(joined.records.count, kept.records.count + 1)
        XCTAssertEqual(joined.records.filter { $0.date == id(back: 40) }.count, 1, "older days are not read again")
        XCTAssertTrue(joined.hasRead(through: id(back: 59)))
        XCTAssertFalse(again.state.refreshFailed)
        XCTAssertEqual(memory.history(for: 1), joined, "kept for the next visit")
    }

    /// A span needing older days than kept reads on back from where the kept records end.
    func testALongerSpanReadsOnFromTheKeptEnd() async throws {
        let rows = (0..<120).map { record(id(back: $0)) }
        let school = School(rows: rows, today: id(back: 0))
        let memory = CardRecordsMemory()
        _ = await firstVisit(school, memory: memory)
        await school.clear()

        let again = loader(school, memory: memory)
        again.setTarget(id(back: 89))
        await again.reload()
        await settled(again)
        let queries = await school.queries
        XCTAssertEqual(queries.map(\.end), [id(back: 0), id(back: 70), id(back: 84)])
        XCTAssertTrue(again.state.history?.hasRead(through: id(back: 89)) ?? false)
        XCTAssertEqual(again.state.history?.records.count, 98)
    }

    /// Kept yesterday: not shown as today's, but still joined after the newest range.
    func testKeptYesterdayIsJoinedButNotShownFirst() async throws {
        let yesterday = cal.date(byAdding: .day, value: -1, to: noon)!
        let rows = (1..<90).map { record(id(back: $0)) }
        let school = School(rows: rows, today: id(back: 1))
        let memory = CardRecordsMemory()
        let first = loader(school, memory: memory, now: yesterday)
        first.setTarget(id(back: 29, from: yesterday))
        await first.reload()
        await settled(first)

        let todaySchool = School(rows: rows + [record(id(back: 0))], today: id(back: 0))
        await todaySchool.hold()
        let again = loader(todaySchool, memory: memory)
        again.setTarget(id(back: 13))
        let visit = Task { await again.reload() }
        await held(todaySchool)
        XCTAssertEqual(again.state.phase, .loading)
        await todaySchool.release()
        await visit.value
        await settled(again)
        let queries = await todaySchool.queries
        XCTAssertEqual(queries.count, 1)
        XCTAssertTrue(again.state.history?.hasRead(through: id(back: 42)) ?? false, "yesterday's 42 days back")
    }

    /// Someone else's records (another stamp) are not used.
    func testAnotherPersonsRecordsAreNotUsed() async throws {
        let rows = (0..<40).map { record(id(back: $0)) }
        let school = School(rows: rows, today: id(back: 0))
        let memory = CardRecordsMemory()
        _ = await firstVisit(school, memory: memory)
        await school.clear()
        XCTAssertNil(memory.history(for: 2))

        let other = loader(school, memory: memory, stamp: 2)
        other.setTarget(id(back: 59))
        await other.reload()
        await settled(other)
        let queries = await school.queries
        XCTAssertGreaterThan(queries.count, 1, "read from today")
        XCTAssertEqual(memory.history(for: 2), other.state.history)
        XCTAssertNil(memory.history(for: 1))
    }

    /// The newest range fails: the kept records stay, said to be as last read.
    func testAFailedRefreshKeepsTheKeptRecords() async throws {
        let rows = (0..<70).map { record(id(back: $0)) }
        let school = School(rows: rows, today: id(back: 0))
        let memory = CardRecordsMemory()
        let visited = await firstVisit(school, memory: memory)
        let kept = try XCTUnwrap(visited)
        await school.fail(true)
        let again = loader(school, memory: memory)
        again.setTarget(id(back: 59))
        await again.reload()
        await settled(again)
        XCTAssertEqual(again.state.phase, .loaded)
        XCTAssertEqual(again.state.history, kept)
        XCTAssertTrue(again.state.refreshFailed)
        XCTAssertFalse(again.state.moreFailed)

        // A pull reads from today afresh.
        await school.fail(false)
        await school.clear()
        await again.reload()
        await settled(again)
        XCTAssertFalse(again.state.refreshFailed)
        let queries = await school.queries
        XCTAssertEqual(queries.first?.begin, id(back: 13))
        XCTAssertEqual(queries.map(\.end).last, id(back: 56), "a pull reads every range again")
    }

    /// Without kept records, home's last records fill the list until the first page comes; the
    /// read's own then take over, each record once.
    func testHomesRecordsShowUntilTheFirstPage() async throws {
        let rows = (0..<20).map { record(id(back: $0)) }
        let school = School(rows: rows, today: id(back: 0))
        let home = CardActivity(records: rows.filter { $0.date >= id(back: 6) }.map { var r = $0; r.voucher = nil; return r },
                                begin: id(back: 6), end: id(back: 0), complete: true)
        await school.hold()
        let first = loader(school, memory: CardRecordsMemory(), prefill: home)
        first.setTarget(id(back: 13))
        let visit = Task { await first.reload() }
        await held(school)
        XCTAssertEqual(first.state.phase, .loaded)
        XCTAssertEqual(first.state.history?.records.count, 7)
        XCTAssertFalse(first.state.history?.hasRead(through: id(back: 0)) ?? true)

        await school.release()
        await visit.value
        await settled(first)
        let history = try XCTUnwrap(first.state.history)
        XCTAssertEqual(history.records.count, 14)
        XCTAssertTrue(history.records.allSatisfy { $0.voucher != nil })
    }

    /// The first page failing leaves home's records shown, with the retry at the list's end.
    func testHomesRecordsStayWhenTheFirstPageFails() async throws {
        let school = School(rows: [], today: id(back: 0))
        await school.fail(true)
        let home = CardActivity(records: [record(id(back: 1))], begin: id(back: 6), end: id(back: 0), complete: true)
        let first = loader(school, memory: nil, prefill: home)
        await first.reload()
        XCTAssertEqual(first.state.phase, .loaded)
        XCTAssertEqual(first.state.history?.records.count, 1)
        XCTAssertTrue(first.state.moreFailed)
    }
}
