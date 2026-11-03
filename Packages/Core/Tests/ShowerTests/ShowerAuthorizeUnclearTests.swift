import XCTest
@testable import Core
import CoreTestSupport

/// An authorize the platform answered with a code the app doesn't know: nothing reached the
/// controller, so no water ran and there is nothing to settle. The page, the status line and
/// Siri say the water didn't start, keep the platform's own words, and never talk about a
/// settlement; the check before the next start stays.
final class ShowerAuthorizeUnclearTests: XCTestCase {
    let machine = "11223344"

    func failedAuthorize(_ e: ServiceError) -> ShowerState {
        var s = ShowerReducer.reduce(.idle, .start(machineID: machine, preferredPeripheral: nil)).0
        s = ShowerReducer.reduce(s, .connected(peripheralID: "P", probe: FakeFrames.identity(machine))).0
        return ShowerReducer.reduce(s, .authorizeFailed(e)).0
    }

    func siri(_ s: ShowerState) -> String? {
        guard case .failure(let f) = ShowerActionOutcome.after(start: true, s, notice: nil) else { return nil }
        return f.message
    }

    func testThePlatformsWordsAreShownWithoutSettlementWording() throws {
        let s = failedAuthorize(.rejected(.lxt6, code: "1", message: "余额不足"))
        XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
        XCTAssertEqual(s.failure?.needsReview, true, "still waits for the check")
        XCTAssertFalse(s.canStart)

        let page = try XCTUnwrap(ShowerPage(s))
        XCTAssertEqual(page.phase, .unsure)
        let copy = try XCTUnwrap(page.authorizeUnclear)
        XCTAssertEqual(copy.title, "水没开")
        XCTAssertEqual(copy.body, ShowerAuthorizeUnclearText.body + "学校提示：余额不足")
        XCTAssertEqual(ShowerDisplay.title(s), "水没开。学校提示：余额不足")
        XCTAssertEqual(ShowerDisplay.failureTitle(s.failure), "水没开。学校提示：余额不足")
        XCTAssertEqual(siri(s), "水没开。学校提示：余额不足。打开校日常核对一下再开始。")

        for text in [copy.title, copy.body, ShowerDisplay.title(s), siri(s) ?? ""] {
            XCTAssertFalse(text.contains("结算"), text)
        }
        for text in [copy.body, ShowerDisplay.title(s), siri(s) ?? ""] {
            XCTAssertTrue(text.contains("余额不足"), text)
        }
    }

    func testWithoutWordsItSaysTheWaterDidNotStart() throws {
        for e in [ServiceError.timedOut, .uncertain(.lxt6), .rejected(.lxt6, code: "500", message: "  ")] {
            let s = failedAuthorize(e)
            XCTAssertEqual(s.failure?.reason, .authorizeUncertain, "\(e)")
            let copy = try XCTUnwrap(ShowerPage(s)?.authorizeUnclear, "\(e)")
            XCTAssertEqual(copy.title, "水没开")
            XCTAssertEqual(copy.body, "学校那边没给准话，所以没开水。先去学校的热水记录里看看有没有多记一笔，看过了点「我在学校记录里核对过了」，再重新开始。")
            XCTAssertEqual(ShowerDisplay.title(s), "水没开")
            XCTAssertEqual(siri(s), "水没开。打开校日常核对一下再开始。")
        }
    }

    /// The platform's sentence already ends a clause: Siri doesn't add a second full stop.
    func testSiriDoesNotDoubleTheFullStop() {
        let s = failedAuthorize(.rejected(.lxt6, code: "1", message: "余额不足。"))
        XCTAssertEqual(siri(s), "水没开。学校提示：余额不足。打开校日常核对一下再开始。")
    }

    /// The platform said OK but its authorization can't be used (another machine, a bad
    /// payload or id): nothing was written to the controller, so it reads like an unclear answer.
    func testAnUnusableAuthorizationSaysTheWaterDidNotStart() throws {
        var s = ShowerReducer.reduce(.idle, .start(machineID: machine, preferredPeripheral: nil)).0
        s = ShowerReducer.reduce(s, .connected(peripheralID: "P", probe: FakeFrames.identity(machine))).0
        s = ShowerReducer.reduce(s, .authorized(ShowerAuthorization(machineID: "99999999", payload: Data(count: 15),
                                                                    authorizationID: "001122FF"), at: Date())).0
        XCTAssertEqual(s.failure?.reason, .authorizationInvalid)
        XCTAssertEqual(s.failure?.needsReview, true, "still waits for the check")
        XCTAssertFalse(s.canStart)

        let page = try XCTUnwrap(ShowerPage(s))
        XCTAssertEqual(page.phase, .unsure)
        XCTAssertEqual(page.authorizeUnclear, ShowerPageCopy(title: "水没开", body: ShowerAuthorizeUnclearText.body))
        XCTAssertEqual(ShowerDisplay.title(s), "水没开")
        XCTAssertEqual(siri(s), "水没开。打开校日常核对一下再开始。")
        XCTAssertEqual(ShowerActionFailure.blockedText(s.failure), "水没开。打开校日常核对一下再开始。")
        XCTAssertEqual(ShowerHomeReview(s.failure), ShowerHomeReview(button: "去核对", caption: "水没开"))
    }

    /// Other unsure faces keep their own copy.
    func testOnlyAnUnclearAuthorizeUsesThisCopy() {
        for reason in [ShowerFailureReason.closeUnconfirmed, .settleRefused, .settleUncertain, .settleUnconfirmed] {
            let s = ShowerState(phase: .failed, machineID: machine,
                                failure: ShowerFailure(reason: reason, needsReview: true, error: .rejected(.lxt6, code: "1", message: "合成提示")))
            XCTAssertNil(ShowerPage(s)?.authorizeUnclear, reason.rawValue)
        }
    }
}
