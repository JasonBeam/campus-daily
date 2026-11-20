import XCTest
import Core

/// 「最近一次用水」 on 清爽's 热水 page: the shower the home tile calls 「上次 11 分钟 · ¥1.32」.
final class ShowerLastUseTests: XCTestCase {
    let ended = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheTilesLastShower() {
        let last = ShowerLastUse.of(minutes: 11, cost: Decimal(string: "1.32"), ended: ended)
        XCTAssertEqual(last, ShowerLastUse(minutes: 11, cost: Decimal(string: "1.32"), ended: ended))
        XCTAssertEqual(last?.duration, "11 分钟")
        XCTAssertEqual(last?.amount, "¥1.32")
    }

    /// No minutes, no last shower: the tile says nothing and the card isn't shown.
    func testNoneWithoutMinutes() {
        XCTAssertNil(ShowerLastUse.of(minutes: nil, cost: Decimal(string: "1.32"), ended: ended))
    }

    /// Settled with no amount read, or no end time kept: the card still shows what is known.
    func testWithoutCostOrDate() {
        let last = ShowerLastUse.of(minutes: 8, cost: nil, ended: nil)
        XCTAssertEqual(last?.duration, "8 分钟")
        XCTAssertNil(last?.amount)
        XCTAssertNil(last?.ended)
    }

    /// When it was settled, as home's 「最近」 writes it (`UpdateTimeText.recent`): 「今天 06:54」,
    /// 「昨天 18:43」, 「11月18日 08:41」, 24-hour and without the year, in the school's days.
    func testEndedReadsAsHomeRecents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        let now = at(20, 7, 30)
        XCTAssertEqual(ShowerLastUse.when(at(20, 6, 54), now: now, calendar: calendar), "今天 06:54")
        XCTAssertEqual(ShowerLastUse.when(at(19, 18, 43), now: now, calendar: calendar), "昨天 18:43")
        XCTAssertEqual(ShowerLastUse.when(at(10, 8, 41), now: now, calendar: calendar), "11月10日 08:41")
        XCTAssertEqual(ShowerLastUse.when(at(10, 8, 41), now: now, calendar: calendar),
                       UpdateTimeText.recent(at(10, 8, 41), now: now, calendar: calendar))
        let last = ShowerLastUse.of(minutes: 9, cost: nil, ended: at(19, 18, 43))
        XCTAssertEqual(last?.endedText(now: now, calendar: calendar), "昨天 18:43")
        XCTAssertNil(ShowerLastUse.of(minutes: 9, cost: nil, ended: nil)?.endedText(now: now, calendar: calendar))
    }
}
