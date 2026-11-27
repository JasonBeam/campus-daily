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
        let warm = SpendStatsText(theme:.warm, calendar:calendar)
        let clear = SpendStatsText(theme:.clear, calendar:calendar)

        // Fallback (no timestamp)
        XCTAssertEqual(warm.refreshFailed, "最新的记录没读到，这里显示上次读到的。下拉再试。")
        XCTAssertEqual(clear.refreshFailed, "未能读取最新记录，当前显示此前读取的内容；可下拉重试")

        // Cached today with `savedAt` (24-hour clock)
        let savedToday = calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:8, minute:30))!
        let cachedToday = calendar.startOfDay(for:now)
        XCTAssertEqual(warm.refreshFailed(savedAt:savedToday, cachedToday:cachedToday, now:now),
                       "最新的记录没读到，这里只到今天 08:30。下拉再试。")
        XCTAssertEqual(clear.refreshFailed(savedAt:savedToday, cachedToday:cachedToday, now:now),
                       "未能读取最新记录，当前内容截至今天 08:30；可下拉重试")

        // Cached earlier day (`cached.today`, no space between month and day)
        let twoDaysAgo = calendar.date(from:DateComponents(year:2026, month:11, day:22, hour:21, minute:15))!
        let twoDaysAgoStart = calendar.startOfDay(for:twoDaysAgo)
        XCTAssertEqual(warm.refreshFailed(savedAt:twoDaysAgo, cachedToday:twoDaysAgoStart, now:now),
                       "最新的记录没读到，这里只到 11月22日。下拉再试。")
        XCTAssertEqual(clear.refreshFailed(savedAt:twoDaysAgo, cachedToday:twoDaysAgoStart, now:now),
                       "未能读取最新记录，当前内容截至 11月22日；可下拉重试")
    }

    func testCrossDayOfflineCacheAnchorsStatsOnCachedDayWithoutTodayLabel() async throws {
        let twoDaysAgo = calendar.date(byAdding:.day, value:-2, to:now)!
        let school = School()
        let memory = CardRecordsMemory()

        // First visit two days ago caches records anchored on 2026-11-22.
        let sampleThen = SampleData.recordsSource(now:twoDaysAgo, delay:.milliseconds(1))
        let sourceThen = CardRecordsSource(stamp:{ 0 }, page:{ query, stamp in
            try await sampleThen.page(query, stamp)
        }, calendar:sampleThen.calendar, memory:memory)
        let defaults = SampleDefaults()
        defaults.set("month", forKey:SpendSpan.storeKey)
        let first = CardRecordsModel(source:sourceThen, preferences:defaults, now:{ twoDaysAgo })
        await first.reload()
        try await settled(first)

        // Two days later, offline: cached records stay anchored on 11月22日 with no 「今天」 label.
        await school.fail(true)
        let sampleNow = SampleData.recordsSource(now:now, delay:.milliseconds(1))
        let sourceNow = CardRecordsSource(stamp:{ 0 }, page:{ query, stamp in
            if await school.failing { throw Unreadable() }
            return try await sampleNow.page(query, stamp)
        }, calendar:sampleNow.calendar, memory:memory)
        let again = CardRecordsModel(source:sourceNow, preferences:defaults, now:{ [now] in now })
        await again.reload()
        try await settled(again)

        XCTAssertTrue(again.refreshFailed)
        let stats = try XCTUnwrap(again.stats)
        XCTAssertEqual(stats.bars.last?.id, "20261122")
        XCTAssertEqual(stats.bars.last?.isCurrent, false)
        XCTAssertEqual(stats.bars.last?.axisLabel, "11月22日")
        XCTAssertNotEqual(stats.bars.last?.axisLabel, "今天")
        let cachedDay = try XCTUnwrap(again.cachedToday)
        XCTAssertEqual(SpendStatsText(theme:.warm, calendar:calendar)
            .refreshFailed(savedAt:again.cachedSavedAt, cachedToday:cachedDay, now:now),
            "最新的记录没读到，这里只到 11月22日。下拉再试。")
    }

    func testLoadMoreOlderSpanDoesNotAdvanceOfflineAsOfTime() async throws {
        let at0830 = calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:8, minute:30))!
        let at1200 = calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:12, minute:0))!
        let at1215 = calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:12, minute:15))!

        var clock = at0830
        let school = School()
        let memory = CardRecordsMemory()
        let sample = SampleData.recordsSource(now:at0830, delay:.milliseconds(1))
        let source = CardRecordsSource(stamp:{ 0 }, page:{ query, stamp in
            if await school.failing { throw Unreadable() }
            return try await sample.page(query, stamp)
        }, calendar:sample.calendar, memory:memory)
        let defaults = SampleDefaults()
        defaults.set("week", forKey:SpendSpan.storeKey)

        // 08:30: open 7-day span (reads newest 14-day range).
        let first = CardRecordsModel(source:source, preferences:defaults, now:{ clock })
        await first.reload()
        try await settled(first)
        XCTAssertEqual(first.cachedSavedAt, at0830)
        XCTAssertEqual(first.state.cachedLatestReadAt, at0830)

        // 12:00: switch to 30-day span (reads older pages only, does NOT re-read today's range).
        clock = at1200
        first.statsSpan = .month
        try await settled(first)
        XCTAssertEqual(first.cachedSavedAt, at0830, "older pagination must not bump latestReadAt to 12:00")
        XCTAssertEqual(first.state.cachedLatestReadAt, at0830)

        // 12:15: offline reopen shows 「今天 08:30」, not 「今天 12:00」.
        clock = at1215
        await school.fail(true)
        let again = CardRecordsModel(source:source, preferences:defaults, now:{ clock })
        await again.reload()
        try await settled(again)
        XCTAssertTrue(again.refreshFailed)
        XCTAssertEqual(again.cachedSavedAt, at0830)
        XCTAssertEqual(again.state.cachedLatestReadAt, at0830)
        let line = SpendStatsText(theme:.warm, calendar:calendar)
            .refreshFailed(savedAt:again.cachedSavedAt,
                           cachedToday:again.cachedToday, now:at1215)
        XCTAssertEqual(line, "最新的记录没读到，这里只到今天 08:30。下拉再试。")
    }

    func testLocalDiskCacheWriteAppliesCompleteProtectionAndExcludesBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xrc-card-cache-attr-\(UUID().uuidString)", isDirectory:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let fs = LocalCardHistoryFileSystem()
        try fs.createDirectory(at:root)
        let file = root.appendingPathComponent("cache.v1.json")
        // Write twice so APFS atomic replacement is exercised.
        try fs.writeProtectedFile(Data("{\"v\":1}".utf8), to:file)
        try fs.writeProtectedFile(Data("{\"v\":2}".utf8), to:file)

        let dirValues = try root.resourceValues(forKeys:[.isExcludedFromBackupKey])
        XCTAssertEqual(dirValues.isExcludedFromBackup, true)
        let fileValues = try file.resourceValues(forKeys:[.isExcludedFromBackupKey])
        XCTAssertEqual(fileValues.isExcludedFromBackup, true)
        XCTAssertEqual(try Data(contentsOf:file), Data("{\"v\":2}".utf8))
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(simulator)
        // iOS Simulator stores files on the macOS host APFS where NSFileProtectionKey reads back nil;
        // on a physical iOS device this verifies NSFileProtectionComplete survives atomic replacement.
        let attrs = try FileManager.default.attributesOfItem(atPath:file.path)
        XCTAssertEqual(attrs[.protectionKey] as? FileProtectionType, .complete)
        #endif
    }
}
