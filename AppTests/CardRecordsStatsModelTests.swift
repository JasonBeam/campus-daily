//
//  CardRecordsStatsModelTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 校园卡记录's stats over the sample: read back as far as the span needs, the span and the term's
/// start day kept in the graph's preferences. Today is fixed: Tuesday 2026-11-24 noon.
@MainActor final class CardRecordsStatsModelTests: XCTestCase {
    private var calendar: Calendar { SampleData.calendar }
    private var now: Date { calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:12))! }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from:DateComponents(year:y, month:m, day:d))! }
    private func id(_ date: Date) -> String { SchoolCalendar.dayString(date, calendar:calendar) }
    private func id(back days: Int) -> String {
        id(calendar.date(byAdding:.day, value:-days, to:calendar.startOfDay(for:now))!)
    }

    /// The pages asked for.
    private actor Queries {
        var list: [CardHistoryQuery] = []
        func add(_ query: CardHistoryQuery) { list.append(query) }
        func clear() { list = [] }
        func oldest() -> String? { list.map(\.begin).min() }
    }

    /// The sample's records on the fixed today; a page fails when `fails` says so.
    private func source(_ queries: Queries? = nil,
                        fails: @escaping @Sendable (CardHistoryQuery) -> Bool = { _ in false }) -> CardRecordsSource {
        let sample = SampleData.recordsSource(now:now, delay:.milliseconds(1))
        return CardRecordsSource(stamp:{ 0 }, page:{ query, stamp in
            await queries?.add(query)
            if fails(query) { throw ServiceError.offline }
            return try await sample.page(query, stamp)
        }, calendar:sample.calendar)
    }

    private func model(_ defaults: SampleDefaults, _ source: CardRecordsSource? = nil) -> CardRecordsModel {
        CardRecordsModel(source:source ?? self.source(), preferences:defaults, now:{ [now] in now })
    }

    private func settled(_ model: CardRecordsModel, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1000 {
            if model.phase == .loaded, !model.statsLoading, !model.loadingMore { return }
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTFail("the stats never came", file:file, line:line)
    }

    func testEachSpanReadsBackFarEnoughForItsStats() async throws {
        let defaults = SampleDefaults()
        let m = model(defaults)
        XCTAssertTrue(m.statsLoading)
        XCTAssertNil(m.stats)
        await m.reload()
        try await settled(m)
        let week = try XCTUnwrap(m.stats)
        XCTAssertEqual(week.span, .week)
        XCTAssertEqual(week.bars.last?.id, "20261124")
        XCTAssertNotNil(week.versusPrevious, "the 7 days before are read too")
        XCTAssertFalse(m.statsFailed)

        m.statsSpan = .month
        XCTAssertEqual(defaults.string(forKey:SpendSpan.storeKey), "month")
        try await settled(m)
        XCTAssertEqual(m.stats?.span, .month)
        XCTAssertNotNil(m.stats?.versusPrevious)

        m.statsSpan = .term
        try await settled(m)
        let term = try XCTUnwrap(m.stats)
        XCTAssertEqual(term.termStart, "20260901")
        XCTAssertGreaterThan(term.total, .zero)
        XCTAssertTrue(m.history?.hasRead(through:"20260901") ?? false)
    }

    /// Back from 本学期 to 7 天: a pull reads back 14 days, not to the term's start again.
    func testBackToTheWeekAPullReadsNoFurtherThanTheWeekNeeds() async throws {
        let queries = Queries()
        let defaults = SampleDefaults()
        defaults.set("term", forKey:SpendSpan.storeKey)
        let m = model(defaults, source(queries))
        await m.reload()
        try await settled(m)
        let termOldest = await queries.oldest()
        XCTAssertLessThanOrEqual(termOldest ?? "", "20260901")

        m.statsSpan = .week
        try await settled(m)
        XCTAssertEqual(m.stats?.span, .week)
        await queries.clear()
        await m.reload()
        try await settled(m)
        try await Task.sleep(for:.milliseconds(50))
        let oldest = await queries.oldest()
        XCTAssertEqual(oldest, id(back:13), "today's range holds the 14 days")
        XCTAssertFalse(m.history?.hasRead(through:"20260901") ?? true)
        XCTAssertNotNil(m.stats?.versusPrevious)
    }

    /// 本学期 chosen while its pages are read, then 30 天: the read stops once the 60 days are in.
    func testAShorterSpanStopsAReadRunning() async throws {
        let queries = Queries()
        let m = model(SampleDefaults(), source(queries))
        await m.reload()
        try await settled(m)
        m.statsSpan = .term
        m.statsSpan = .month
        try await settled(m)
        try await Task.sleep(for:.milliseconds(50))
        let oldest = await queries.oldest()
        XCTAssertGreaterThan(oldest ?? "", "20260901")
        XCTAssertEqual(m.stats?.span, .month)
    }

    func testTheSpanChosenIsKept() async throws {
        let defaults = SampleDefaults()
        defaults.set("term", forKey:SpendSpan.storeKey)
        let m = model(defaults)
        XCTAssertEqual(m.statsSpan, .term)
        let later = CardRecordsModel(source:source(), now:{ [now] in now })
        XCTAssertEqual(later.statsSpan, .week, "nothing kept before preferences are given")
        later.bind(defaults)
        XCTAssertEqual(later.statsSpan, .term)
    }

    func testSettingTheTermStartKeepsItAndResetGoesBackToTheDefault() async throws {
        let defaults = SampleDefaults()
        let m = model(defaults)
        m.statsSpan = .term
        await m.reload()
        try await settled(m)
        XCTAssertFalse(m.termStartIsCustom)
        XCTAssertEqual(m.termStart, day(2026, 9, 1))
        XCTAssertEqual(m.termStart, m.defaultTermStart)

        let set = day(2026, 11, 14)
        XCTAssertTrue(m.setTermStart(set))
        XCTAssertTrue(m.termStartIsCustom)
        XCTAssertEqual(m.termStart, set)
        XCTAssertEqual(defaults.string(forKey:TermStartStore.key), "20261114")
        try await settled(m)
        XCTAssertEqual(m.stats?.termStart, "20261114")

        m.resetTermStart()
        XCTAssertFalse(m.termStartIsCustom)
        XCTAssertNil(defaults.object(forKey:TermStartStore.key))
        XCTAssertEqual(m.termStart, m.defaultTermStart)
    }

    func testThePickerOffersFromFourWeeksBeforeTheTermThroughToday() {
        let m = model(SampleDefaults())
        XCTAssertEqual(m.termStartRange.lowerBound, day(2026, 8, 4))
        XCTAssertEqual(m.termStartRange.upperBound, day(2026, 11, 24))
        XCTAssertTrue(m.setTermStart(m.termStartRange.lowerBound))
        XCTAssertEqual(m.termStart, day(2026, 8, 4))
    }

    /// A day that would not count (after today, another term's) is refused: the day set before
    /// stays, kept and in effect.
    func testADayThatWouldNotCountIsRefusedAndTheOneSetStays() {
        let defaults = SampleDefaults()
        let m = model(defaults)
        XCTAssertTrue(m.setTermStart(day(2026, 8, 28)))
        for refused in [day(2026, 11, 25), day(2026, 3, 2), day(2026, 8, 3), day(2025, 11, 24)] {
            XCTAssertFalse(m.setTermStart(refused), id(refused))
            XCTAssertEqual(m.customTermStart, day(2026, 8, 28), id(refused))
            XCTAssertEqual(defaults.string(forKey:TermStartStore.key), "20260828", id(refused))
            XCTAssertTrue(m.termStartIsCustom)
            XCTAssertEqual(m.termStart, day(2026, 8, 28))
        }
    }

    func testAFailedFirstReadFailsTheStats() async {
        let m = model(SampleDefaults(), source(fails:{ _ in true }))
        await m.reload()
        XCTAssertTrue(m.statsFailed)
        XCTAssertFalse(m.statsLoading)
        XCTAssertNil(m.stats)
    }

    /// An older page failing after the span itself was read: the stats show, without the
    /// comparison; the footer offers to try again.
    func testAnOlderPageFailingAfterTheSpanShowsTheStatsWithoutTheComparison() async throws {
        let defaults = SampleDefaults()
        defaults.set("month", forKey:SpendSpan.storeKey)
        // Ranges back to 41 days are read; the next one (to 55 days back) fails.
        let edge = id(back:41)
        let m = model(defaults, source(fails:{ $0.begin < edge }))
        await m.reload()
        try await settled(m)
        XCTAssertTrue(m.moreFailed)
        let month = try XCTUnwrap(m.stats)
        XCTAssertEqual(month.span, .month)
        XCTAssertNil(month.versusPrevious)
        XCTAssertGreaterThan(month.total, .zero)
        XCTAssertFalse(m.statsFailed)
        XCTAssertFalse(m.statsLoading)
    }

    /// An older page failing before the span was read: the stats fail (the records stay).
    func testAnOlderPageFailingBeforeTheSpanFailsTheStats() async throws {
        let defaults = SampleDefaults()
        defaults.set("month", forKey:SpendSpan.storeKey)
        let today = id(now)
        let m = model(defaults, source(fails:{ $0.end != today }))
        await m.reload()
        try await settled(m)
        XCTAssertTrue(m.moreFailed)
        XCTAssertEqual(m.phase, .loaded)
        XCTAssertNotNil(m.history)
        XCTAssertNil(m.stats)
        XCTAssertTrue(m.statsFailed)
        XCTAssertFalse(m.statsLoading)
    }
}
