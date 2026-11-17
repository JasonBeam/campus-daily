import XCTest
import Core
@testable import XiaoRiChang

/// 「就是这间」 binds the dorm's controller; when the hot-water account could not be read, the
/// dorm screen can't fix it: the guide goes on with the reason, and only a real choice opens it.
@MainActor
final class DormAutoBindTests: XCTestCase {
    func testAFailedReadIsNotAChoice() {
        XCTAssertEqual(DormSetupFlow.readOutcome(identityRead:false, issue:"账户余额不足，请充值后使用"),
                       .failed("账户余额不足，请充值后使用"))
        XCTAssertEqual(DormSetupFlow.readOutcome(identityRead:false, issue:ShowerModel.platformMissingText), .unavailable)
        XCTAssertNil(DormSetupFlow.readOutcome(identityRead:true, issue:"宿舍列表没读到，重新选一下。"),
                     "read: the rooms decide")
        XCTAssertNil(DormSetupFlow.readOutcome(identityRead:false, issue:nil))
    }

    func testTheGuideGoesOnWithTheReasonAfterAFailedRead() {
        XCTAssertEqual(OnboardingView.next(after:.failed("账户余额不足")), .advance(note:"账户余额不足"))
        XCTAssertEqual(OnboardingView.next(after:.bound), .advance(note:nil))
        XCTAssertEqual(OnboardingView.next(after:.unavailable), .advance(note:nil))
        XCTAssertEqual(OnboardingView.next(after:.needsChoice), .choose)
    }

    func testClearSetupKeepsTheReasonOnItsPageAfterAFailedRead() {
        XCTAssertEqual(ClearSetupDormPage.next(after:.failed("账户余额不足")), .stay(note:"账户余额不足"))
        XCTAssertEqual(ClearSetupDormPage.next(after:.bound), .confirm)
        XCTAssertEqual(ClearSetupDormPage.next(after:.unavailable), .confirm)
        XCTAssertEqual(ClearSetupDormPage.next(after:.needsChoice), .choose)
    }
}
