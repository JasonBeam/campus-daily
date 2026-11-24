//
//  TermStartTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
@testable import Core

/// 「本学期」's first day: 3月1日 / 9月1日 by default, a day the user set for its own term only.
final class TermStartTests: XCTestCase {
    let cal = SchoolCalendar.shanghai

    func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func id(_ date: Date) -> String { SchoolCalendar.dayString(date, calendar: cal) }

    func defaultStart(_ y: Int, _ m: Int, _ d: Int) -> String {
        id(TermStart.defaultStart(today: day(y, m, d, hour: 12), calendar: cal))
    }

    func start(_ today: Date, custom: Date?) -> String { id(TermStart.start(today: today, custom: custom, calendar: cal)) }

    func testDefaultIsMarchFirstOrSeptemberFirst() {
        XCTAssertEqual(defaultStart(2026, 3, 1), "20260301")
        XCTAssertEqual(defaultStart(2026, 6, 15), "20260301")
        XCTAssertEqual(defaultStart(2026, 8, 31), "20260301")
        XCTAssertEqual(defaultStart(2026, 9, 1), "20260901")
        XCTAssertEqual(defaultStart(2026, 11, 24), "20260901")
        XCTAssertEqual(defaultStart(2026, 12, 31), "20260901")
    }

    func testJanuaryAndFebruaryBelongToLastSeptember() {
        XCTAssertEqual(defaultStart(2027, 1, 1), "20260901")
        XCTAssertEqual(defaultStart(2027, 2, 28), "20260901")
        XCTAssertEqual(defaultStart(2028, 2, 29), "20270901")
    }

    func testTheSchoolsDayDecides() {
        // 00:30 on 9月1日 in Shanghai is still 8月31日 in most of the world.
        let early = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 0, minute: 30))!
        XCTAssertEqual(id(TermStart.defaultStart(today: early, calendar: cal)), "20260901")
    }

    func testNoDaySetIsTheDefault() {
        XCTAssertEqual(start(day(2026, 11, 24), custom: nil), "20260901")
    }

    func testADaySetCountsInItsTerm() {
        let today = day(2026, 11, 24, hour: 12)
        XCTAssertEqual(start(today, custom: day(2026, 9, 7)), "20260907")
        XCTAssertEqual(start(today, custom: day(2026, 8, 24)), "20260824", "late August opens the autumn term")
        XCTAssertTrue(TermStart.isActive(custom: day(2026, 9, 7), today: today, calendar: cal))
    }

    func testADaySetEndsWithTheNextDefaultTerm() {
        let set = day(2026, 9, 7)
        XCTAssertEqual(start(day(2027, 2, 28, hour: 23), custom: set), "20260907", "January and February are still its term")
        XCTAssertEqual(start(day(2027, 3, 1, hour: 8), custom: set), "20270301")
        XCTAssertFalse(TermStart.isActive(custom: set, today: day(2027, 3, 1), calendar: cal))
    }

    func testALateFebruaryStartOpensTheSpringTerm() {
        let set = day(2027, 2, 20)
        XCTAssertEqual(start(day(2027, 2, 25), custom: set), "20270220")
        XCTAssertEqual(start(day(2027, 3, 10), custom: set), "20270220", "still its term after 3月1日")
        XCTAssertEqual(start(day(2027, 8, 31), custom: set), "20270220")
        XCTAssertEqual(start(day(2027, 9, 1), custom: set), "20270901")
    }

    func testAJanuaryDayBelongsToTheAutumnTerm() {
        let set = day(2027, 1, 10)
        XCTAssertEqual(start(day(2027, 2, 1), custom: set), "20270110")
        XCTAssertEqual(start(day(2027, 3, 1), custom: set), "20270301")
    }

    // MARK: Boundaries

    func testTheDefaultTurnsOverAtMidnightOnMarchFirstAndSeptemberFirst() {
        let lastFebruary = cal.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 23, minute: 59))!
        XCTAssertEqual(id(TermStart.defaultStart(today: lastFebruary, calendar: cal)), "20260901")
        XCTAssertEqual(id(TermStart.defaultStart(today: day(2027, 3, 1), calendar: cal)), "20270301")
        let lastAugust = cal.date(from: DateComponents(year: 2027, month: 8, day: 31, hour: 23, minute: 59))!
        XCTAssertEqual(id(TermStart.defaultStart(today: lastAugust, calendar: cal)), "20270301")
        XCTAssertEqual(id(TermStart.defaultStart(today: day(2027, 9, 1), calendar: cal)), "20270901")
    }

    func testFebruaryTwentiethBelongsToTheSpringTermThrough31August() {
        let set = day(2027, 2, 20)
        XCTAssertEqual(id(TermStart.term(of: set, calendar: cal)), "20270301")
        for today in [day(2027, 2, 20), day(2027, 2, 28, hour: 23), day(2027, 3, 1), day(2027, 6, 1), day(2027, 8, 31, hour: 23)] {
            XCTAssertTrue(TermStart.isActive(custom: set, today: today, calendar: cal), id(today))
            XCTAssertEqual(start(today, custom: set), "20270220", id(today))
        }
        XCTAssertFalse(TermStart.isActive(custom: set, today: day(2027, 9, 1), calendar: cal))
        XCTAssertEqual(start(day(2027, 9, 1), custom: set), "20270901")
    }

    func testLateAugustBelongsToTheAutumnTermThroughFebruary() {
        for set in [day(2026, 8, 25), day(2026, 8, 31)] {
            let setID = id(set)
            XCTAssertEqual(id(TermStart.term(of: set, calendar: cal)), "20260901", setID)
            // Active from its own day, though the default is still the spring term's.
            for today in [set, day(2026, 8, 31, hour: 23), day(2026, 9, 1), day(2026, 12, 31), day(2027, 2, 28, hour: 23)] {
                XCTAssertTrue(TermStart.isActive(custom: set, today: today, calendar: cal), "\(setID) \(id(today))")
                XCTAssertEqual(start(today, custom: set), setID, id(today))
            }
            XCTAssertFalse(TermStart.isActive(custom: set, today: day(2027, 3, 1), calendar: cal), setID)
            XCTAssertEqual(start(day(2027, 3, 1), custom: set), "20270301", setID)
        }
    }

    func testADayAfterTodayDoesNotCount() {
        XCTAssertEqual(start(day(2026, 11, 24), custom: day(2026, 11, 30)), "20260901")
    }

    func testADayFromAnOlderTermDoesNotCount() {
        XCTAssertEqual(start(day(2026, 11, 24), custom: day(2026, 3, 2)), "20260901")
    }

    func testPickerRangeIsTheEarliestDayThisTermTakesThroughToday() {
        let range = TermStart.pickerRange(today: day(2026, 11, 24, hour: 15), calendar: cal)
        XCTAssertEqual(id(range.lowerBound), "20260804", "28 days before 9月1日")
        XCTAssertEqual(range.upperBound, day(2026, 11, 24))
        XCTAssertEqual(id(TermStart.pickerRange(today: day(2026, 8, 20, hour: 15), calendar: cal).lowerBound), "20260201")
        XCTAssertEqual(id(TermStart.pickerRange(today: day(2027, 2, 10, hour: 15), calendar: cal).lowerBound), "20260804")
    }

    /// Whatever the picker offers counts today, and the day before it does not: no choice is
    /// kept only to be ignored.
    func testEveryDayThePickerOffersCountsAndTheDayBeforeItDoesNot() {
        for today in [day(2026, 11, 24, hour: 15), day(2026, 8, 20, hour: 15), day(2026, 8, 31, hour: 23),
                      day(2026, 9, 1), day(2027, 2, 10, hour: 15), day(2027, 2, 28, hour: 23), day(2027, 3, 1)] {
            let range = TermStart.pickerRange(today: today, calendar: cal)
            var d = range.lowerBound
            while d <= range.upperBound {
                XCTAssertTrue(TermStart.isActive(custom: d, today: today, calendar: cal), "\(id(d)) on \(id(today))")
                XCTAssertEqual(start(today, custom: d), id(d))
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            let before = cal.date(byAdding: .day, value: -1, to: range.lowerBound)!
            XCTAssertFalse(TermStart.isActive(custom: before, today: today, calendar: cal), "\(id(before)) on \(id(today))")
        }
    }

    // MARK: Store

    final class Preferences: PreferenceStorage {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    func testStoreKeepsTheDayAsSchoolDayText() throws {
        let prefs = Preferences()
        let store = TermStartStore(preferences: prefs, calendar: cal)
        XCTAssertNil(store.custom)
        store.set(day(2026, 9, 7, hour: 23))
        XCTAssertEqual(prefs.values[TermStartStore.key] as? String, "20260907")
        XCTAssertEqual(TermStartStore.key, "records.termStart")
        XCTAssertEqual(try XCTUnwrap(store.custom), day(2026, 9, 7))
        store.clear()
        XCTAssertNil(store.custom)
    }

    func testStoreIgnoresWhatItCannotRead() {
        let prefs = Preferences()
        let store = TermStartStore(preferences: prefs, calendar: cal)
        let unreadable: [Any] = ["2026097", "20261332", "20260230", "abcdefgh", 20260907]
        for bad in unreadable {
            prefs.values[TermStartStore.key] = bad
            XCTAssertNil(store.custom, "\(bad)")
        }
    }
}
