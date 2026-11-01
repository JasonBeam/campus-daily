import XCTest
@testable import Core

/// The widget footer says how old the numbers are: a reading from yesterday or earlier
/// never looks like today's.
final class UpdateTimeTextTests: XCTestCase {
    static var shanghai: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    let calendar = shanghai

    func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    var now: Date { date(10, 30, 9, 15) }

    func footer(_ d: Date) -> String { UpdateTimeText.widgetUpdated(d, now: now, calendar: calendar) }

    /// 最近 counts days in the school's time zone, like 昨天花了: 00:30 in Shanghai is today there,
    /// whatever zone the phone is set to.
    func testRecentRowsCountDaysInTheSchoolTimeZone() {
        XCTAssertEqual(UpdateTimeText.recent(date(10, 30, 9, 12), now: now), "刚刚")
        XCTAssertEqual(UpdateTimeText.recent(date(10, 30, 0, 30), now: now), "今天 00:30")
        XCTAssertEqual(UpdateTimeText.recent(date(10, 29, 23, 50), now: now), "昨天 23:50")
        XCTAssertEqual(UpdateTimeText.recent(date(10, 26, 19, 2), now: now), "周一 19:02")
        XCTAssertEqual(UpdateTimeText.recent(date(10, 20, 19, 2), now: now), "10月20日 19:02")
        // The default is the school's calendar, not the device's: the same answers without passing one.
        XCTAssertEqual(UpdateTimeText.recent(date(10, 29, 23, 50), now: now, calendar: calendar), "昨天 23:50")
    }

    func testToday() {
        XCTAssertEqual(footer(date(10, 30, 8, 10)), "8:10 更新")
        XCTAssertEqual(footer(date(10, 30, 0, 0)), "0:00 更新", "midnight is today")
    }

    func testYesterdayCarriesTheWord() {
        XCTAssertEqual(footer(date(10, 29, 22, 10)), "昨天 22:10 更新")
        XCTAssertEqual(footer(date(10, 29, 0, 5)), "昨天 0:05 更新")
    }

    func testOlderCarriesDateAndTime() {
        XCTAssertEqual(footer(date(10, 28, 23, 59)), "10月28日 23:59 更新")
        XCTAssertEqual(footer(date(9, 1, 7, 3)), "9月1日 7:03 更新")
    }

    /// Yesterday is relative to the face's own time, not the wall clock of the test run.
    func testYesterdayIsRelativeToNow() {
        let later = date(10, 31, 0, 1)
        XCTAssertEqual(UpdateTimeText.widgetUpdated(date(10, 30, 23, 50), now: later, calendar: calendar), "昨天 23:50 更新")
        XCTAssertEqual(UpdateTimeText.widgetUpdated(date(10, 29, 23, 50), now: later, calendar: calendar), "10月29日 23:50 更新")
    }

    /// The stale face uses the same time before 「 · 打开 App 更新」.
    func testStaleStampMatchesTheFooter() {
        XCTAssertEqual(UpdateTimeText.stamp(date(10, 30, 8, 10), now: now, calendar: calendar), "8:10")
        XCTAssertEqual(UpdateTimeText.stamp(date(10, 29, 22, 10), now: now, calendar: calendar), "昨天 22:10")
        XCTAssertEqual(UpdateTimeText.stamp(date(10, 29 - 1, 22, 10), now: now, calendar: calendar), "10月28日 22:10")
    }

    /// The calendar decides the day: 23:30 UTC on the 29th is already the 30th in Shanghai.
    func testDayBoundaryFollowsTheCalendarTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let t = utc.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 23, minute: 30))!
        XCTAssertEqual(UpdateTimeText.widgetUpdated(t, now: now, calendar: calendar), "7:30 更新")
    }

    /// Small widget, stale: the clock only today, the day alone otherwise.
    func testSmallStaleLineIsDateOnlyWhenNotToday() {
        func line(_ d: Date) -> String { UpdateTimeText.dayOrClock(d, now: now, calendar: calendar) }
        XCTAssertEqual(line(date(10, 30, 8, 10)), "8:10")
        XCTAssertEqual(line(date(10, 29, 22, 10)), "昨天")
        XCTAssertEqual(line(date(10, 29, 0, 1)), "昨天")
        XCTAssertEqual(line(date(10, 28, 22, 10)), "10月28日")
    }
}
