import XCTest
@testable import Core

/// Each kept shower as two lines on both themes' lists: the start time (or, without one, the
/// reason), then the controller and the reason; newest first. Fakes only.
final class ShowerRetainedLinesTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTimeReadsMonthDayAndClock() {
        XCTAssertEqual(ShowerRetainedText.time(date(11, 16, 21, 5), calendar: calendar), "11月16日 21:05")
        XCTAssertEqual(ShowerRetainedText.time(date(3, 5, 8, 7), calendar: calendar), "3月5日 08:07")
    }

    func testNewestFirstAndUndatedLast() {
        let summary = ShowerRetainedSummary(entries: [
            .init(started: date(11, 14, 20, 0), machine: "11223344", reason: .stopped),
            .init(started: nil, machine: "11223344", reason: .authorizeUnclear),
            .init(started: date(11, 16, 21, 5), machine: "AABBCCDD", reason: .closeUnconfirmed),
        ])
        let lines = ShowerRetainedText.lines(summary, reason: ShowerRetainedText.Clear.reason) {
            ShowerRetainedText.time($0, calendar: self.calendar)
        }
        XCTAssertEqual(lines, [
            .init(title: "11月16日 21:05", detail: "AABBCCDD · 关水未确认"),
            .init(title: "11月14日 20:00", detail: "11223344 · 停水未结算"),
            .init(title: "授权未确认", detail: "11223344"),
        ])
    }

    func testWithoutMachineOrTime() {
        let summary = ShowerRetainedSummary(entries: [
            .init(started: date(11, 16, 21, 5), machine: nil, reason: .settleUnconfirmed),
            .init(started: nil, machine: nil, reason: .stopped),
        ])
        let lines = ShowerRetainedText.lines(summary, reason: ShowerRetainedText.Warm.reason) { _ in "T" }
        XCTAssertEqual(lines, [.init(title: "T", detail: "结算没确认"), .init(title: "在水控上按停的", detail: nil)])
    }

    /// VoiceOver reads a row as one sentence.
    func testSpokenJoinsBothLines() {
        XCTAssertEqual(ShowerRetainedText.Line(title: "11月16日 21:05", detail: "AABBCCDD · 关水未确认").spoken,
                       "11月16日 21:05，AABBCCDD · 关水未确认")
        XCTAssertEqual(ShowerRetainedText.Line(title: "授权未确认", detail: nil).spoken, "授权未确认")
    }
}
