import XCTest
@testable import Core

/// What the recharge page says when it could not be prepared, and whether it offers signing in again.
final class RechargeOpenIssueTests: XCTestCase {
    /// The widget is refreshing (it holds the lease): nothing is wrong with the login.
    func testAnUpdateInProgressAsksToWaitAndOffersNoSignIn() {
        let issue = RechargeOpenIssue(SchoolLoginFailure.busy)
        XCTAssertEqual(issue.text, "正在更新，等一下再试。")
        XCTAssertFalse(issue.offersSignIn)
    }

    func testAnExpiredLoginOffersSignIn() {
        let issue = RechargeOpenIssue(ServiceError.sessionExpired(.ecykt))
        XCTAssertEqual(issue.text, ServiceError.sessionExpired(.ecykt).userMessage)
        XCTAssertTrue(issue.offersSignIn)
    }

    func testAnythingElseSaysThePageDidNotOpen() {
        let issue = RechargeOpenIssue(CocoaError(.fileReadUnknown))
        XCTAssertEqual(issue.text, "学校页面暂时打不开，再试一次。")
        XCTAssertTrue(issue.offersSignIn)
    }
}
