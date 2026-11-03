import XCTest
@testable import Core

/// The home card of a record that waits for its check: an authorize the platform answered
/// unclearly, or with an authorization that can't be used, started no water and settled
/// nothing, so it says the water didn't start; every other record keeps the settlement words.
final class ShowerHomeReviewTests: XCTestCase {
    func testAnUnclearAuthorizeSaysTheWaterDidNotStart() {
        let review = ShowerHomeReview(ShowerFailure(reason: .authorizeUncertain, needsReview: true, error: .uncertain(.lxt6)))
        XCTAssertEqual(review, ShowerHomeReview(button: "去核对", caption: "水没开"))
        XCTAssertFalse(review.caption.contains("结算"))
        XCTAssertFalse(review.button.contains("结算"))
    }

    func testAnUnclearAuthorizeWithThePlatformsWordsShowsThem() {
        let failure = ShowerFailure(reason: .authorizeUncertain, needsReview: true,
                                    error: .rejected(.lxt6, code: "1", message: "余额不足"))
        XCTAssertEqual(ShowerHomeReview(failure), ShowerHomeReview(button: "去核对", caption: "水没开。学校提示：余额不足"))
    }

    func testAnUnconfirmedSettlementKeepsTheSettlementWords() {
        for reason: ShowerFailureReason in [.closeUnconfirmed, .settleRefused, .settleUncertain, .settleUnconfirmed] {
            XCTAssertEqual(ShowerHomeReview(ShowerFailure(reason: reason, needsReview: true)), .settlement, reason.rawValue)
        }
        XCTAssertEqual(ShowerHomeReview.settlement, ShowerHomeReview(button: "核对上次结算", caption: "上次洗澡不确定结算了没有"))
    }

    func testAnUnusableAuthorizationSaysTheWaterDidNotStart() {
        XCTAssertEqual(ShowerHomeReview(ShowerFailure(reason: .authorizationInvalid, needsReview: true)),
                       ShowerHomeReview(button: "去核对", caption: "水没开"))
    }

    func testNoFailureKeepsTheSettlementWords() {
        XCTAssertEqual(ShowerHomeReview(nil), .settlement)
    }
}
