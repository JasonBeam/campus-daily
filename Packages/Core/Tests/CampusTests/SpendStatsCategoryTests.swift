//
//  SpendStatsCategoryTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
@testable import Core

/// The stats over the categories counted: a category left out (电费 by default) is out of the
/// total, the average, the comparison and the bars, and stays on the category list at its amount.
final class SpendStatsCategoryTests: XCTestCase {
    let cal = SchoolCalendar.shanghai
    /// Tuesday 2026-11-24 12:00 in Shanghai.
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))! }
    var autumn: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 1))! }

    var vouchers = 0
    func record(_ date: String, _ yuan: String, _ title: String = "POS消费示例面馆", flag: String? = "1") -> CardRecord {
        vouchers += 1
        return CardRecord(date: date, time: "120000", title: title, amount: Money(yuanString: yuan)!, balanceAfter: nil,
                          direction: flag, voucher: String(format: "99%018d", vouchers))
    }

    /// The week and the week before it read, as the records page reads them.
    func stats(_ rows: [CardRecord], _ included: Set<CardRecordKind>, span: SpendSpan = .week) throws -> SpendStats {
        let rows = rows.sorted { ($0.date, $0.time) > ($1.date, $1.time) }
        let through = SpendStats.firstDayNeeded(span: span, today: noon, termStart: autumn, calendar: cal)
        var h = CardHistory(now: noon)
        while let q = h.nextQuery, !h.hasRead(through: through) { h.receive(SampleData.recordPage(rows, q), for: q) }
        return try XCTUnwrap(SpendStats.make(span: span, history: h, termStart: autumn, included: included, calendar: cal))
    }

    var rows: [CardRecord] {
        [record("20261124", "12.00"), record("20261122", "120.00", "电费"), record("20261120", "2.00", "蓝牙热水"),
         record("20261115", "10.00"), record("20261113", "50.00", "购电")]
    }

    /// 「转入电控」 is 电费 by its name, and money out only with flag 「1」: without it 转入 reads as
    /// money in, as it does for 「转入水控」, and no category counts it.
    func testElectricityTransfersCountOnlyWithTheirPaymentFlag() throws {
        let paid = record("20261123", "30.00", "转入电控")
        let unflagged = record("20261123", "30.00", "转入电控", flag: nil)
        let water = record("20261123", "10.00", "转入水控", flag: nil)
        XCTAssertEqual([paid.kind, unflagged.kind, water.kind], [.electricity, .electricity, .shower])
        XCTAssertEqual(CardSpend.of(paid, calendar: cal), .paid(day: "20261123", amount: Money(fen: 3000)))
        XCTAssertEqual(CardSpend.of(unflagged, calendar: cal), .moneyIn)
        XCTAssertEqual(CardSpend.of(water, calendar: cal), .moneyIn, "the same as 转入水控")

        let meal = record("20261124", "12.00")
        let on = try stats([meal, paid], Set(SpendCategories.all))
        XCTAssertEqual(on.total, Money(fen: 4200))
        XCTAssertEqual(on.shares.first { $0.kind == .electricity }?.spent, Money(fen: 3000))
        XCTAssertEqual(try stats([meal, paid], SpendCategories.defaultIncluded).total, Money(fen: 1200))

        let unpaid = try stats([meal, unflagged, water], Set(SpendCategories.all))
        XCTAssertEqual(unpaid.total, Money(fen: 1200))
        XCTAssertEqual(unpaid.shares.map(\.kind), [.canteen], "money in: on no category's list")
        XCTAssertEqual(unpaid.unsureDays, 0)
    }

    func testTheDefaultLeavesElectricityOut() {
        XCTAssertEqual(SpendCategories.all, [.canteen, .shower, .laundry, .electricity, .other])
        XCTAssertEqual(SpendCategories.defaultIncluded, [.canteen, .shower, .laundry, .other])
    }

    func testElectricityLeftOutIsOutOfTotalAverageComparisonAndBars() throws {
        let s = try stats(rows, SpendCategories.defaultIncluded)
        XCTAssertEqual(s.total, Money(fen: 1400))
        XCTAssertEqual(s.dailyAverage, Money(fen: 200))
        XCTAssertEqual(s.versusPrevious, Money(fen: 400), "14.00 − 10.00: the 50.00 of 购电 before is left out too")
        XCTAssertEqual(s.bars.map(\.spent.fen), [0, 0, 200, 0, 0, 0, 1200])
        XCTAssertFalse(s.isEmpty)

        let all = try stats(rows, Set(SpendCategories.all))
        XCTAssertEqual(all.total, Money(fen: 13400))
        XCTAssertEqual(all.dailyAverage, Money(fen: 1914))
        XCTAssertEqual(all.versusPrevious, Money(fen: 7400), "134.00 − 60.00")
        XCTAssertEqual(all.bars.map(\.spent.fen), [0, 0, 200, 0, 12000, 0, 1200])
    }

    /// Biggest first, counted or not: turning one off or on moves nothing. Shares are of the
    /// counted total; one left out has none.
    func testAPlaceOnTheListKeepsWhetherCountedOrNot() throws {
        let off = try stats(rows, SpendCategories.defaultIncluded)
        XCTAssertEqual(off.shares.map(\.kind), [.electricity, .canteen, .shower])
        XCTAssertEqual(off.shares.map(\.spent.fen), [12000, 1200, 200])
        XCTAssertEqual(off.shares.map(\.included), [false, true, true])
        XCTAssertEqual(off.shares[0].fraction, 0)
        XCTAssertEqual(off.shares[1].fraction, 12.0 / 14.0, accuracy: 1e-9)
        XCTAssertEqual(off.shares.map(\.fraction).reduce(0, +), 1, accuracy: 1e-9)

        let on = try stats(rows, Set(SpendCategories.all))
        XCTAssertEqual(on.shares.map(\.kind), off.shares.map(\.kind))
        XCTAssertEqual(on.shares.map(\.included), [true, true, true])
        XCTAssertEqual(on.shares[0].fraction, 120.0 / 134.0, accuracy: 1e-9)

        let canteenOff = try stats(rows, [.shower, .electricity])
        XCTAssertEqual(canteenOff.shares.map(\.kind), [.electricity, .canteen, .shower, .laundry, .other],
                       "the ones left out at nothing spent follow, in their own order")
        XCTAssertEqual(canteenOff.shares.map(\.included), [true, false, true, false, false])
        XCTAssertEqual(canteenOff.total, Money(fen: 12200))
    }

    /// Left out with nothing spent on it, a category is still listed, so it can be counted again.
    func testACategoryLeftOutIsListedAtNothingSpent() throws {
        let s = try stats([record("20261124", "12.00")], SpendCategories.defaultIncluded)
        XCTAssertEqual(s.shares.map(\.kind), [.canteen, .electricity])
        XCTAssertEqual(s.shares.map(\.spent), [Money(fen: 1200), .zero])
        XCTAssertEqual(s.shares.map(\.included), [true, false])
    }

    /// Spending only on a category left out: nothing counted, but the category is listed, and so
    /// are those counted, at nothing spent, so it shows which are on.
    func testOnlyACategoryLeftOutIsEmptyButListed() throws {
        let s = try stats([record("20261122", "120.00", "电费")], SpendCategories.defaultIncluded)
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.shares.map(\.kind), [.electricity, .canteen, .shower, .laundry, .other])
        XCTAssertEqual(s.shares.map(\.spent.fen), [12000, 0, 0, 0, 0])
        XCTAssertEqual(s.shares.map(\.included), [false, true, true, true, true])
        XCTAssertTrue(s.shares.allSatisfy { $0.fraction == 0 })

        let one = try stats([record("20261122", "120.00", "电费"), record("20261123", "8.00")], [.shower])
        XCTAssertEqual(one.shares.map(\.kind), [.electricity, .canteen, .shower, .laundry, .other])
        XCTAssertEqual(one.shares.map(\.included), [false, false, true, false, false])
    }

    /// Something counted was spent: a category counted with nothing spent stays off the list.
    func testACountedCategoryWithNothingSpentIsNotListedWhileOthersCount() throws {
        let s = try stats([record("20261122", "120.00", "电费"), record("20261123", "8.00")], SpendCategories.defaultIncluded)
        XCTAssertEqual(s.shares.map(\.kind), [.electricity, .canteen])
    }

    /// A record that may be money in or out makes its day unsure only when its category counts.
    func testADoubtOnACategoryLeftOutLeavesItsDaySure() throws {
        let rows = [record("20261124", "12.00"), record("20261121", "30.00", "电费", flag: "3"), record("20261116", "1.00")]
        let off = try stats(rows, SpendCategories.defaultIncluded)
        XCTAssertEqual(off.unsureDays, 0)
        XCTAssertEqual(off.versusPrevious, Money(fen: 1100))
        let on = try stats(rows, Set(SpendCategories.all))
        XCTAssertEqual(on.unsureDays, 1)
        XCTAssertEqual(on.bars.filter(\.unsure).map(\.id), ["20261121"])
    }

    /// The term: weeks count the categories counted only.
    func testTermWeeksLeaveACategoryOut() throws {
        let s = try stats(rows, SpendCategories.defaultIncluded, span: .term)
        XCTAssertEqual(s.total, Money(fen: 2400))
        XCTAssertEqual(s.bars.last?.spent, Money(fen: 1200), "Monday 23rd and today")
        XCTAssertNil(s.versusPrevious)
    }

    // MARK: Store

    func testTheStoreKeepsWhatIsLeftOut() {
        let defaults = SampleDefaults()
        let store = SpendCategoryStore(preferences: defaults)
        XCTAssertEqual(SpendCategoryStore.key, "records.statsCategories")
        XCTAssertEqual(store.included, SpendCategories.defaultIncluded)

        store.set([.canteen, .electricity])
        XCTAssertEqual(defaults.object(forKey: SpendCategoryStore.key) as? [String], ["shower", "laundry", "other"])
        XCTAssertEqual(store.included, [.canteen, .electricity])

        store.set(Set(SpendCategories.all))
        XCTAssertEqual(store.included, Set(SpendCategories.all), "电费 counted once turned on")

        store.clear()
        XCTAssertNil(defaults.object(forKey: SpendCategoryStore.key))
        XCTAssertEqual(store.included, SpendCategories.defaultIncluded)
    }

    func testAnUnreadableOrEmptyChoiceIsTheDefault() {
        let defaults = SampleDefaults()
        let store = SpendCategoryStore(preferences: defaults)
        defaults.set("electricity", forKey: SpendCategoryStore.key)
        XCTAssertEqual(store.included, SpendCategories.defaultIncluded)
        defaults.set(SpendCategories.all.map(\.rawValue), forKey: SpendCategoryStore.key)
        XCTAssertEqual(store.included, SpendCategories.defaultIncluded, "nothing counted is never kept")
        defaults.set(["electricity", "someday"], forKey: SpendCategoryStore.key)
        XCTAssertEqual(store.included, SpendCategories.defaultIncluded, "an unknown name is passed over")
    }
}
