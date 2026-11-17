import XCTest
import Core
@testable import XiaoRiChang

/// 「就是这间」 binds the dorm's controller; when the hot-water account could not be read, the
/// dorm screen can't fix it: the guide goes on with the reason, and only a real choice opens it.
@MainActor
final class DormAutoBindTests: XCTestCase {
    func testAFailedReadIsNotAChoice() {
        XCTAssertEqual(DormSetupFlow.readOutcome(identityRead:false, issue:"账户余额不足，请充值后使用", failure:.lowBalance),
                       .failed(.lowBalance))
        XCTAssertEqual(DormSetupFlow.readOutcome(identityRead:false, issue:"学校系统这次没通过，再试一次。", failure:.other),
                       .failed(.other))
        XCTAssertEqual(DormSetupFlow.readOutcome(identityRead:false, issue:"x", failure:nil), .failed(.other))
        XCTAssertEqual(DormSetupFlow.readOutcome(identityRead:false, issue:ShowerModel.platformMissingText, failure:nil), .unavailable)
        XCTAssertNil(DormSetupFlow.readOutcome(identityRead:true, issue:"宿舍列表没读到，重新选一下。", failure:nil),
                     "read: the rooms decide")
        XCTAssertNil(DormSetupFlow.readOutcome(identityRead:false, issue:nil, failure:nil))
    }

    func testTheGuideGoesOnWithTheReasonAfterAFailedRead() {
        XCTAssertEqual(OnboardingView.next(after:.failed(.lowBalance)),
                       .advance(note:"热水平台说余额不足，这次没绑上热水。在热水小程序充值后，到设置的「热水」里再绑。电费和校园卡照常用。"))
        XCTAssertEqual(OnboardingView.next(after:.failed(.other)),
                       .advance(note:"这次没读到热水账号，先跳过。之后到设置的「热水」里再绑，电费和校园卡照常用。"))
        XCTAssertEqual(OnboardingView.next(after:.bound), .advance(note:nil))
        XCTAssertEqual(OnboardingView.next(after:.unavailable), .advance(note:nil))
        XCTAssertEqual(OnboardingView.next(after:.needsChoice), .choose)
    }

    func testClearSetupKeepsTheReasonOnItsPageAfterAFailedRead() {
        XCTAssertEqual(ClearSetupDormPage.next(after:.failed(.lowBalance)),
                       .stay(note:"热水平台提示余额不足，暂未绑定热水；充值后可在设置 › 热水中重新绑定，电费与校园卡不受影响"))
        XCTAssertEqual(ClearSetupDormPage.next(after:.failed(.other)),
                       .stay(note:"热水账号读取失败，暂未绑定热水；可在设置 › 热水中重新绑定，电费与校园卡不受影响"))
        XCTAssertEqual(ClearSetupDormPage.next(after:.bound), .confirm)
        XCTAssertEqual(ClearSetupDormPage.next(after:.unavailable), .confirm)
        XCTAssertEqual(ClearSetupDormPage.next(after:.needsChoice), .choose)
    }
}
