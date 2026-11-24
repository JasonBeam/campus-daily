//
//  CardRecordsSpeedModelTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 校园卡记录's stats come as soon as the span is read, the comparison after. Today is fixed: Tuesday
/// 2026-11-24 noon, on the sample's records.
@MainActor final class CardRecordsSpeedModelTests: XCTestCase {
    private var calendar: Calendar { SampleData.calendar }
    private var now: Date { calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:12))! }
    private func id(back days: Int) -> String {
        SchoolCalendar.dayString(calendar.date(byAdding:.day, value:-days, to:calendar.startOfDay(for:now))!, calendar:calendar)
    }

    /// Holds the pages `holds` says until released; counts every page asked for.
    private actor Gate {
        var holding = true
        var waiting: [CheckedContinuation<Void, Never>] = []
        var asked: [CardHistoryQuery] = []
        func ask(_ query: CardHistoryQuery, hold: Bool) async {
            asked.append(query)
            if hold, holding { await withCheckedContinuation { waiting.append($0) } }
        }
        func release() { holding = false; waiting.forEach { $0.resume() }; waiting = [] }
        func clear() { asked = [] }
        var isWaiting: Bool { !waiting.isEmpty }
    }

    private func source(_ gate: Gate, holds: @escaping @Sendable (CardHistoryQuery) -> Bool) -> CardRecordsSource {
        let sample = SampleData.recordsSource(now:now, delay:.milliseconds(1))
        return CardRecordsSource(stamp:{ 0 }, page:{ query, stamp in
            await gate.ask(query, hold:holds(query))
            return try await sample.page(query, stamp)
        }, calendar:sample.calendar)
    }

    private func until(_ condition: @autoclosure () -> Bool, _ what: String,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for:.milliseconds(5))
        }
        XCTFail(what, file:file, line:line)
    }

    func testTheSpansStatsComeBeforeTheComparison() async throws {
        let gate = Gate()
        let defaults = SampleDefaults()
        defaults.set("month", forKey:SpendSpan.storeKey)
        // The period before the 30 days (from 42 days back) waits.
        let edge = id(back:41)
        let m = CardRecordsModel(source:source(gate) { $0.begin < edge }, preferences:defaults, now:{ [now] in now })
        XCTAssertFalse(m.comparisonLoading)
        await m.reload()
        try await until(m.stats != nil, "the 30 days' stats never came")
        let first = try XCTUnwrap(m.stats)
        XCTAssertNil(first.versusPrevious)
        XCTAssertTrue(m.comparisonLoading)
        XCTAssertFalse(m.statsLoading)
        XCTAssertFalse(m.statsFailed)
        XCTAssertGreaterThan(first.total, .zero)

        await gate.release()
        try await until(!m.comparisonLoading && !m.loadingMore, "the comparison never came")
        let full = try XCTUnwrap(m.stats)
        XCTAssertNotNil(full.versusPrevious)
        XCTAssertEqual(full.total, first.total, "only the comparison came")
        XCTAssertEqual(full.bars, first.bars)
    }

    /// 本学期 has no comparison: nothing more to wait for once the term is read.
    func testTheTermHasNoComparisonToWaitFor() async throws {
        let gate = Gate()
        await gate.release()
        let defaults = SampleDefaults()
        defaults.set("term", forKey:SpendSpan.storeKey)
        let m = CardRecordsModel(source:source(gate) { _ in false }, preferences:defaults, now:{ [now] in now })
        await m.reload()
        try await until(m.stats != nil && !m.loadingMore, "the term's stats never came")
        XCTAssertFalse(m.comparisonLoading)
    }
}
