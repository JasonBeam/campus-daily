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
}
