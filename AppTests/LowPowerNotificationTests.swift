import XCTest
import Core
@testable import XiaoRiChang

/// The low-electricity notification's words are unchanged; its 今晚/明晚 come from the school's
/// days left (`preUseDay`), counted from when the reading was taken.
@MainActor
final class LowPowerNotificationTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier:.gregorian)
        c.timeZone = TimeZone(identifier:"Asia/Shanghai")!
        return c
    }()
    var now: Date { calendar.date(from:DateComponents(year:2026, month:11, day:10, hour:9, minute:15))! }

    func meter(kwh: Decimal, days: Decimal?) -> Meter {
        Meter(comAddress:"M1", name:"3栋108", remainingKWh:kwh, estimatedDaysLeft:days)
    }

    func testTheNightComesFromTheSchoolsDays() {
        XCTAssertEqual(Reminders.powerBody(meter(kwh:13.6, days:1.2), readAt:now, now:now, calendar:calendar),
                       "只剩 13.6 度，大约能用到明晚。记得充电费。")
        XCTAssertEqual(Reminders.powerBody(meter(kwh:3.4, days:0.3), readAt:now, now:now, calendar:calendar),
                       "只剩 3.4 度，大约能用到今晚。记得充电费。")
    }

    func testManyDaysOrNoUsableEstimateIsTheShortForm() {
        for days: Decimal? in [19, nil, 0, -1, 400] {
            XCTAssertEqual(Reminders.powerBody(meter(kwh:9.9, days:days), readAt:now, now:now, calendar:calendar), "只剩 9.9 度了，记得充电费。",
                           "\(String(describing: days))")
        }
    }

    /// Settings changed today 09:15 and the last reading is yesterday 09:15 (8.4 度, 1.2 天):
    /// it runs out this afternoon, so 今晚 as on home, never 明晚.
    func testAnOldReadingCountsFromWhenItWasRead() {
        let yesterday = calendar.date(byAdding:.day, value:-1, to:now)!
        XCTAssertEqual(Reminders.powerBody(meter(kwh:8.4, days:1.2), readAt:yesterday, now:now, calendar:calendar),
                       "只剩 8.4 度，大约能用到今晚。记得充电费。")
    }

    /// No reading time, or the estimated end already passed: only the short form.
    func testNoReadingTimeOrAPassedEndIsTheShortForm() {
        XCTAssertEqual(Reminders.powerBody(meter(kwh:8.4, days:1.2), readAt:nil, now:now, calendar:calendar),
                       "只剩 8.4 度了，记得充电费。")
        let threeDaysAgo = calendar.date(byAdding:.day, value:-3, to:now)!
        XCTAssertEqual(Reminders.powerBody(meter(kwh:8.4, days:1.2), readAt:threeDaysAgo, now:now, calendar:calendar),
                       "只剩 8.4 度了，记得充电费。")
    }
}
