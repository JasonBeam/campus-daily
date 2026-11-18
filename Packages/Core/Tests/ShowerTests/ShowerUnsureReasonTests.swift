import XCTest
@testable import Core
import CoreTestSupport

/// Why an outcome is not known, from the saved record alone (so it is the same after a
/// relaunch), and its words in both themes.
final class ShowerUnsureReasonTests: XCTestCase {
    let machine = "11223344"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func failed(_ reason: ShowerFailureReason, error: ServiceError? = nil, device: ShowerDeviceError? = nil,
                notSent: Bool = false, held: Bool = false) -> ShowerState {
        ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizeSent: true,
                    authorizationID: "001122FF", closeSent: true, consumption: "AB",
                    failure: ShowerFailure(reason: reason, needsReview: true, error: error, deviceError: device,
                                           settleNotSent: notSent, settleHeld: held))
    }

    func testEachUnsureStateMapsToItsReason() {
        // A: the start refused with the unfinished-order answer.
        XCTAssertEqual(ShowerUnsureReason.of(failed(.authorizeUncertain, error: .officialUnfinishedOrder)), .unfinishedOrderAtStart)
        // Any other unclear authorize keeps its own words (水没开).
        XCTAssertNil(ShowerUnsureReason.of(failed(.authorizeUncertain, error: .uncertain(.lxt6))))
        XCTAssertNil(ShowerUnsureReason.of(failed(.authorizeUncertain, error: .rejected(.lxt6, code: "9", message: "x"))))
        XCTAssertNil(ShowerUnsureReason.of(failed(.authorizationInvalid)))
        // B: the settlement may have left, no answer.
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleUncertain, error: .timedOut)), .settleNoAnswer)
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleUncertain, error: .uncertain(.lxt6))), .settleNoAnswer)
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleUnconfirmed)), .settleNoAnswer, "relaunched while it was out")
        // C: the close got no end data, until a check saw the controller stopped.
        XCTAssertEqual(ShowerUnsureReason.of(failed(.closeBusy, device: .busy)), .closeNoAnswer)
        XCTAssertEqual(ShowerUnsureReason.of(failed(.closeUnconfirmed, device: .timedOut)), .closeNoAnswer)
        XCTAssertEqual(ShowerUnsureReason.of(ShowerReducer.restore(ShowerState(phase: .closing, machineID: machine, peripheralID: "P",
                                                                               startedAt: t0, authorizationID: "001122FF",
                                                                               closingFrom: .running, closeSent: true))), .closeNoAnswer)
        var seen = failed(.closeBusy, device: .busy); seen.closeStopSeen = true
        XCTAssertNil(ShowerUnsureReason.of(seen), "the kept words")
        // F, F': the school did not take the settlement.
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleRefused, error: .rejected(.lxt6, code: "9", message: "x"))), .settleRefused)
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleRefused, error: .badRequest(.lxt6))), .settleRefused)
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleRefused, error: .officialUnfinishedOrder)), .unfinishedOrderAtSettle)
        // G: the settlement provably never left (also a frame an older build held back).
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleUnconfirmed, notSent: true)), .settleNotSent)
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleUnconfirmed, notSent: true, held: true)), .settleNotSent)
        // A retry of a held frame that got no answer: it may have left.
        XCTAssertEqual(ShowerUnsureReason.of(failed(.settleUncertain, error: .timedOut, held: true)), .settleNoAnswer)
        // E: a kept failure the record can't tell apart (one another build saved, say).
        var unknown = failed(.settleUnconfirmed); unknown.failure?.reason = .deviceUnavailable
        XCTAssertEqual(ShowerUnsureReason.of(unknown), .other)
    }

    /// D: only once the authorization reached the controller and it did not confirm it.
    func testStartUnconfirmedOnlyAfterTheAuthorizationWentOut() {
        let pending = ShowerState(phase: .writePending, machineID: machine, peripheralID: "P", startedAt: t0, authorizeSent: true,
                                  authorizationID: "001122FF")
        XCTAssertEqual(ShowerUnsureReason.of(pending), .startUnconfirmed)
        var notWritten = pending; notWritten.authorizationNotWritten = true
        XCTAssertNil(ShowerUnsureReason.of(notWritten))
        var stopped = pending; stopped.stateReviewRequired = true
        XCTAssertNil(ShowerUnsureReason.of(stopped), "the kept words")
        for phase in [ShowerPhase.idle, .authorizing, .running, .closing, .settling, .done] {
            var s = pending; s.phase = phase
            XCTAssertNil(ShowerUnsureReason.of(s), "\(phase)")
        }
    }

    /// The other failures and every phase without one: no reason.
    func testFailuresThatAreNotUnsureHaveNoReason() {
        for reason in [ShowerFailureReason.deviceUnavailable, .wrongDevice, .deviceBusy, .authorizeRefused] {
            var s = failed(reason); s.failure?.needsReview = false
            XCTAssertNil(ShowerUnsureReason.of(s), reason.rawValue)
        }
    }

    func testBothThemesHaveTheExactWordsForEveryReason() {
        let warm: [ShowerUnsureReason: String] = [
            .unfinishedOrderAtStart: "学校说还有一单热水没结束，这次没开水。去学校热水小程序看看那一单，扣费去校园卡记录里看，要 1 小时左右才出现。",
            .settleNoAnswer: "结算发出去了，学校没回音，不知道扣没扣。先别再结算，过 1 小时左右去校园卡记录里看看。",
            .closeNoAnswer: "结束发出去了，水控还没回话。先看水停没停，停了就算洗完；费用看校园卡记录，扣费要 1 小时左右才出现。",
            .startUnconfirmed: "开水的结果没收到。有热水就照常洗，洗完点结束；费用看校园卡记录，扣费要 1 小时左右才出现。",
            .settleRefused: "学校没接受这次结算。去校园卡记录里看看扣了没有，扣费要 1 小时左右才出现。",
            .unfinishedOrderAtSettle: "学校说还有一单热水没结束，这次没结算上。去学校热水小程序看看那一单，扣费去校园卡记录里看，要 1 小时左右才出现。",
            .settleNotSent: "结算没发出去。去校园卡记录里看看这次扣了没有，扣费要 1 小时左右才出现。",
            .other: "这次的结果没确认。先别重复操作，去校园卡记录里看看扣了没有，扣费要 1 小时左右才出现。",
        ]
        let clear: [ShowerUnsureReason: String] = [
            .unfinishedOrderAtStart: "学校仍有未完成的热水订单，本次未开水；请在官方热水小程序中核对该订单，费用可在校园卡消费明细中核对，扣费约 1 小时后入账",
            .settleNoAnswer: "结算请求已发出，学校尚未确认结果；请勿重复结算，可在校园卡消费明细中核对，扣费约 1 小时后入账",
            .closeNoAnswer: "结束指令已发出，水控尚未返回结束数据；请确认是否已停水，费用可在校园卡消费明细中核对，扣费约 1 小时后入账",
            .startUnconfirmed: "开水结果未确认；如有出水可正常使用，结束后请点「结束并结算」，费用可在校园卡消费明细中核对，扣费约 1 小时后入账",
            .settleRefused: "学校未接受本次结算；可在校园卡消费明细中核对，扣费约 1 小时后入账",
            .unfinishedOrderAtSettle: "学校仍有未完成的热水订单，本次未能结算；请在官方热水小程序中核对该订单，费用可在校园卡消费明细中核对，扣费约 1 小时后入账",
            .settleNotSent: "结算请求未发出；可在校园卡消费明细中核对，扣费约 1 小时后入账",
            .other: "本次结果未确认；请勿重复操作，可在校园卡消费明细中核对，扣费约 1 小时后入账",
        ]
        for reason in ShowerUnsureReason.allCases {
            XCTAssertEqual(ShowerUnsureText.warm(reason), warm[reason], reason.rawValue)
            XCTAssertEqual(ShowerUnsureText.clear(reason), clear[reason], reason.rawValue)
            XCTAssertTrue(ShowerUnsureText.warm(reason).hasSuffix("。"), reason.rawValue)
            XCTAssertFalse(ShowerUnsureText.clear(reason).hasSuffix("。"), reason.rawValue)
            // G is shown only where 结束 can't be tapped again: no "tap again" words.
            XCTAssertFalse(ShowerUnsureText.warm(reason).contains("再点"), reason.rawValue)
            XCTAssertFalse(ShowerUnsureText.clear(reason).contains("再次点"), reason.rawValue)
        }
    }

    /// Each surface shows the reason's words: the stopped face (both themes), the timer while
    /// the start is unconfirmed (清爽), and the line where the page is not shown.
    func testSurfacesUseTheReason() {
        let busy = failed(.closeBusy, device: .busy)
        XCTAssertEqual(ShowerPage(busy)?.unsure, .closeNoAnswer)
        XCTAssertEqual(ClearShowerText.face(.stopped, unsure: .settleNoAnswer).body, ShowerUnsureText.clear(.settleNoAnswer))
        XCTAssertEqual(ClearShowerText.face(.running, unsure: .startUnconfirmed).body, ShowerUnsureText.clear(.startUnconfirmed))
        XCTAssertEqual(ClearShowerText.face(.running).body, ClearShowerText.runningBody)
        XCTAssertEqual(ClearShowerText.face(.stopped, unsure: nil).body, ClearShowerText.stoppedBody)
    }
}
