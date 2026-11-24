//
//  CardRecordsRefreshFailedTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 校园卡记录 opened again shows the records kept from the last visit; when the newest can't be
/// read, a line over the stats says what is shown, until a pull reads the newest.
@MainActor final class CardRecordsRefreshFailedTests: XCTestCase {
    private var calendar: Calendar { SampleData.calendar }
    private var now: Date { calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:12))! }

    private actor School {
        var failing = false
        func fail(_ on: Bool) { failing = on }
    }

    private struct Unreadable: Error {}

    private func model(_ school: School, memory: CardRecordsMemory) -> CardRecordsModel {
        let sample = SampleData.recordsSource(now:now, delay:.milliseconds(1))
        let source = CardRecordsSource(stamp:{ 0 }, page:{ query, stamp in
            if await school.failing { throw Unreadable() }
            return try await sample.page(query, stamp)
        }, calendar:sample.calendar, memory:memory)
        return CardRecordsModel(source:source, preferences:SampleDefaults(), now:{ [now] in now })
    }

    private func settled(_ model: CardRecordsModel, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1000 {
            if model.phase == .loaded, !model.statsLoading, !model.comparisonLoading, !model.loadingMore { return }
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTFail("the records never settled", file:file, line:line)
    }

    func testTheLineShowsWhenTheNewestCantBeReadAndGoesWithAPull() async throws {
        let school = School()
        let memory = CardRecordsMemory()
        let first = model(school, memory:memory)
        await first.reload()
        try await settled(first)
        XCTAssertFalse(first.refreshFailed)

        await school.fail(true)
        let again = model(school, memory:memory)
        await again.reload()
        try await settled(again)
        XCTAssertTrue(again.refreshFailed, "the kept records show, the newest unread")
        XCTAssertNotNil(again.history)
        XCTAssertNotNil(again.stats)

        await school.fail(false)
        await again.reload()
        try await settled(again)
        XCTAssertFalse(again.refreshFailed, "a pull read the newest")
    }

    func testTheLineSaysWhatIsShownInEachTheme() {
        XCTAssertEqual(SpendStatsText(theme:.warm, calendar:calendar).refreshFailed, "最新的记录没读到，这里是刚才读到的。下拉再试。")
        XCTAssertEqual(SpendStatsText(theme:.clear, calendar:calendar).refreshFailed, "未能读取最新记录，当前显示此前读取的内容；可下拉重试")
    }
}
