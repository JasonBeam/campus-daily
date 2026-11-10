import XCTest
@testable import Core

/// A start and the controller check never run beside each other.
final class ShowerLinkRuleTests: XCTestCase {
    func testNoStartWhileTheControllerCheckRuns() {
        XCTAssertTrue(ShowerLinkRule.mayStart(.idle, ready: true, busy: false, inspecting: false))
        XCTAssertFalse(ShowerLinkRule.mayStart(.idle, ready: true, busy: false, inspecting: true),
                       "the check would disconnect the link after the authorization")
        XCTAssertFalse(ShowerLinkRule.mayStart(ShowerState(phase: .done), ready: true, busy: false, inspecting: true))
    }

    func testNoCheckWhileStartingOrShowering() {
        XCTAssertTrue(ShowerLinkRule.mayInspect(.idle, busy: false, inspecting: false))
        XCTAssertFalse(ShowerLinkRule.mayInspect(.idle, busy: true, inspecting: false), "a start is running")
        XCTAssertFalse(ShowerLinkRule.mayInspect(.idle, busy: false, inspecting: true), "one check at a time")
        for phase in [ShowerPhase.authorizing, .writePending, .running, .closing, .settling] {
            XCTAssertFalse(ShowerLinkRule.mayInspect(ShowerState(phase: phase), busy: false, inspecting: false), phase.rawValue)
        }
        let unsettled = ShowerState(phase: .failed, failure: ShowerFailure(reason: .settleUncertain, needsReview: true))
        XCTAssertFalse(ShowerLinkRule.mayInspect(unsettled, busy: false, inspecting: false))
    }
}
