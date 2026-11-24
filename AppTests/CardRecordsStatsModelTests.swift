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
/// start day kept in the graph's preferences.
@MainActor final class CardRecordsStatsModelTests: XCTestCase {
    private func model(_ defaults: SampleDefaults) -> CardRecordsModel {
        CardRecordsModel(source:SampleData.recordsSource(delay:.milliseconds(1)), preferences:defaults)
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
        XCTAssertEqual(term.termStart, SchoolCalendar.dayString(m.termStart, calendar:m.calendar))
        XCTAssertGreaterThan(term.total, .zero)
        XCTAssertTrue(m.history?.hasRead(through:term.termStart!) ?? false)
    }

    func testTheSpanChosenIsKept() async throws {
        let defaults = SampleDefaults()
        defaults.set("term", forKey:SpendSpan.storeKey)
        let m = model(defaults)
        XCTAssertEqual(m.statsSpan, .term)
        let later = CardRecordsModel(source:SampleData.recordsSource(delay:.milliseconds(1)))
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
        XCTAssertEqual(m.termStart, m.defaultTermStart)

        let set = m.calendar.date(byAdding:.day, value:-10, to:m.calendar.startOfDay(for:Date()))!
        m.setTermStart(set)
        XCTAssertTrue(m.termStartIsCustom)
        XCTAssertEqual(m.termStart, set)
        XCTAssertEqual(defaults.string(forKey:TermStartStore.key), SchoolCalendar.dayString(set, calendar:m.calendar))
        try await settled(m)
        XCTAssertEqual(m.stats?.termStart, SchoolCalendar.dayString(set, calendar:m.calendar))

        m.resetTermStart()
        XCTAssertFalse(m.termStartIsCustom)
        XCTAssertNil(defaults.object(forKey:TermStartStore.key))
        XCTAssertEqual(m.termStart, m.defaultTermStart)
    }

    func testADayOutsideThePickerIsKeptInside() {
        let m = model(SampleDefaults())
        m.setTermStart(Date().addingTimeInterval(86_400 * 30))
        XCTAssertEqual(m.customTermStart, m.termStartRange.upperBound)
    }

    func testAFailedFirstReadFailsTheStats() async {
        let source = CardRecordsSource(stamp:{ 0 }, page:{ _, _ in throw ServiceError.offline }, calendar:SampleData.calendar)
        let m = CardRecordsModel(source:source, preferences:SampleDefaults())
        await m.reload()
        XCTAssertTrue(m.statsFailed)
        XCTAssertFalse(m.statsLoading)
        XCTAssertNil(m.stats)
    }
}
