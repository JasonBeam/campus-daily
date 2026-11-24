//
//  CardRecordsCategoryModelTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
import Core
@testable import XiaoRiChang

/// The categories 校园卡记录's stats count: all but 电费 at first, switched one by one, kept in the
/// graph's preferences, and never the last one turned off. Today is fixed: Tuesday 2026-11-24 noon;
/// the sample pays ¥120 of electricity 20 days back and ¥80 50 days back.
@MainActor final class CardRecordsCategoryModelTests: XCTestCase {
    private var calendar: Calendar { SampleData.calendar }
    private var now: Date { calendar.date(from:DateComponents(year:2026, month:11, day:24, hour:12))! }

    private func model(_ defaults: SampleDefaults) -> CardRecordsModel {
        CardRecordsModel(source:SampleData.recordsSource(now:now, delay:.milliseconds(1)), preferences:defaults,
                         now:{ [now] in now })
    }

    private func settled(_ model: CardRecordsModel, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1000 {
            if model.phase == .loaded, !model.statsLoading, !model.comparisonLoading, !model.loadingMore { return }
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTFail("the stats never came", file:file, line:line)
    }

    func testElectricityIsLeftOutUntilTurnedOnAndTheChoiceIsKept() async throws {
        let defaults = SampleDefaults()
        defaults.set("month", forKey:SpendSpan.storeKey)
        let m = model(defaults)
        XCTAssertEqual(m.includedCategories, SpendCategories.defaultIncluded)
        await m.reload()
        try await settled(m)
        let off = try XCTUnwrap(m.stats)
        let electricity = try XCTUnwrap(off.shares.first { $0.kind == .electricity })
        XCTAssertFalse(electricity.included)
        XCTAssertEqual(electricity.spent, Money(fen:12000))
        XCTAssertEqual(electricity.fraction, 0)

        XCTAssertTrue(m.toggleCategory(.electricity))
        let on = try XCTUnwrap(m.stats, "worked out again from the records read")
        XCTAssertEqual(on.total.fen - off.total.fen, 12000)
        XCTAssertEqual(on.bars.map(\.spent.fen).reduce(0, +) - off.bars.map(\.spent.fen).reduce(0, +), 12000)
        XCTAssertEqual(try XCTUnwrap(on.versusPrevious).fen - (try XCTUnwrap(off.versusPrevious)).fen, 12000 - 8000)
        XCTAssertGreaterThan(on.dailyAverage, off.dailyAverage)
        XCTAssertEqual(on.shares.map(\.kind), off.shares.map(\.kind), "nothing moves on the list")
        XCTAssertTrue(on.shares.allSatisfy(\.included))
        XCTAssertEqual(SpendCategoryStore(preferences:defaults).included, Set(SpendCategories.all))

        let later = model(defaults)
        XCTAssertEqual(later.includedCategories, Set(SpendCategories.all), "kept for the next visit")

        XCTAssertTrue(m.toggleCategory(.electricity))
        XCTAssertEqual(m.stats, off)
    }

    /// The list day totals 「花了」 count every category whatever the stats count.
    func testTheListsDayTotalsKeepElectricity() async throws {
        let defaults = SampleDefaults()
        defaults.set("month", forKey:SpendSpan.storeKey)
        let m = model(defaults)
        await m.reload()
        try await settled(m)
        let history = try XCTUnwrap(m.history)
        let day = SchoolCalendar.dayString(calendar.date(byAdding:.day, value:-20, to:now)!, calendar:calendar)
        let total = try XCTUnwrap(CardDays.groups(history:history, app:[], now:now, calendar:calendar).first { $0.id == day }?.total)
        let bar = try XCTUnwrap(m.stats?.bars.first { $0.id == day })
        XCTAssertEqual(total.fen - bar.spent.fen, 12000)
    }

    /// The last category counted on the list stays on; one left out can always come back. 30 天,
    /// so that 电费 has spending and stays listed once on.
    func testTheLastCategoryCountedIsNotTurnedOff() async throws {
        let defaults = SampleDefaults()
        defaults.set("month", forKey:SpendSpan.storeKey)
        let m = model(defaults)
        await m.reload()
        try await settled(m)
        XCTAssertEqual(Set(try XCTUnwrap(m.stats).shares.map(\.kind)), Set(SpendCategories.all))
        for kind in [CardRecordKind.shower, .laundry, .other] { XCTAssertTrue(m.toggleCategory(kind), "\(kind)") }
        XCTAssertEqual(m.includedCategories, [.canteen])
        XCTAssertFalse(m.toggleCategory(.canteen))
        XCTAssertEqual(m.includedCategories, [.canteen])
        XCTAssertNotNil(m.stats)

        XCTAssertTrue(m.toggleCategory(.electricity))
        XCTAssertTrue(m.toggleCategory(.canteen))
        XCTAssertEqual(m.includedCategories, [.electricity])
        XCTAssertFalse(m.toggleCategory(.electricity))
        XCTAssertFalse(m.toggleCategory(.topUp), "top-ups are never counted")
        XCTAssertEqual(m.includedCategories, [.electricity])
    }

    /// Counted but with nothing spent in the span, a category is not on the list: it does not
    /// keep the last one listed on.
    func testACategoryNotOnTheListDoesNotCountAsLeftOn() async throws {
        let defaults = SampleDefaults()
        SpendCategoryStore(preferences:defaults).set([.canteen, .electricity])
        let m = model(defaults)
        await m.reload()
        try await settled(m)
        XCTAssertFalse(try XCTUnwrap(m.stats).shares.contains { $0.kind == .electricity }, "no electricity paid in the week")
        XCTAssertFalse(m.toggleCategory(.canteen))
        XCTAssertEqual(m.includedCategories, [.canteen, .electricity])

        let unread = model(SampleDefaults())
        for kind in [CardRecordKind.shower, .laundry, .other] { XCTAssertTrue(unread.toggleCategory(kind)) }
        XCTAssertFalse(unread.toggleCategory(.canteen), "before the stats, every category is on the list")
    }
}
