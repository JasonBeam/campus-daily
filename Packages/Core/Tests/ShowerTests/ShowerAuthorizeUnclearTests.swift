import XCTest
@testable import Core
import CoreTestSupport

/// An authorize the platform answered with a code the app doesn't know: nothing reached the
/// controller, so no water ran and there is nothing to settle. The page, the status line and
/// Siri say the water didn't start, keep the platform's own words, and never talk about a
/// settlement; the page is the stopped one (the record is kept, the next shower starts there).
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

        XCTAssertEqual(ShowerPage(s)?.phase, .stopped)
        XCTAssertEqual(ShowerDisplay.title(s), "水没开。学校提示：余额不足")
        XCTAssertEqual(ShowerDisplay.failureTitle(s.failure), "水没开。学校提示：余额不足")
        XCTAssertEqual(siri(s), "水没开。学校提示：余额不足。打开校日常再试一次。")

        for text in [ShowerDisplay.title(s), siri(s) ?? ""] {
            XCTAssertFalse(text.contains("结算"), text)
        }
        for text in [ShowerDisplay.title(s), siri(s) ?? ""] {
            XCTAssertTrue(text.contains("余额不足"), text)
        }
    }

    /// 4060: the school still has an unfinished hot-water order. The record is kept and waits for
    /// its check like any unclear answer; only the words are the school's refusal.
    func testTheSchoolsUnfinishedOrderRefusalIsShown() throws {
        let s = failedAuthorize(.officialUnfinishedOrder)
        XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
        XCTAssertEqual(s.failure?.needsReview, true, "still waits for the check")
        XCTAssertEqual(s.failure?.error, .officialUnfinishedOrder)
        XCTAssertFalse(s.canStart)
        XCTAssertEqual(ShowerPage(s)?.phase, .stopped)
        XCTAssertEqual(ShowerDisplay.title(s), "水没开。学校提示：学校仍有未完成热水订单，请到官方热水小程序核对后重试")
        XCTAssertEqual(siri(s), "水没开。学校提示：学校仍有未完成热水订单，请到官方热水小程序核对后重试。打开校日常再试一次。")
        let debug = DebugError(ServiceError.officialUnfinishedOrder)
        XCTAssertEqual(debug.kind, .rejected)
        XCTAssertEqual(debug.service, .lxt6)
        XCTAssertEqual(debug.code, DebugCode("4060"))
    }

    func testWithoutWordsItSaysTheWaterDidNotStart() throws {
        for e in [ServiceError.timedOut, .uncertain(.lxt6), .rejected(.lxt6, code: "500", message: "  ")] {
            let s = failedAuthorize(e)
            XCTAssertEqual(s.failure?.reason, .authorizeUncertain, "\(e)")
            XCTAssertEqual(ShowerPage(s)?.phase, .stopped, "\(e)")
            XCTAssertEqual(ShowerDisplay.title(s), "水没开")
            XCTAssertEqual(siri(s), "水没开。打开校日常再试一次。")
        }
    }

    /// The platform's sentence already ends a clause: Siri doesn't add a second full stop.
    func testSiriDoesNotDoubleTheFullStop() {
        let s = failedAuthorize(.rejected(.lxt6, code: "1", message: "余额不足。"))
        XCTAssertEqual(siri(s), "水没开。学校提示：余额不足。打开校日常再试一次。")
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

        XCTAssertEqual(ShowerPage(s)?.phase, .stopped)
        XCTAssertEqual(ShowerDisplay.title(s), "水没开")
        XCTAssertEqual(siri(s), "水没开。打开校日常再试一次。")
        XCTAssertEqual(ShowerActionFailure.blockedText(s.failure), "水没开。打开校日常再试一次。")
    }
}
