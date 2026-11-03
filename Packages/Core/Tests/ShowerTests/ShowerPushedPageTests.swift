import XCTest
@testable import Core

/// The shower page pushed on a stack (清爽): when it may be left, and which face it shows.
final class ShowerPushedPageTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func failed(_ reason: ShowerFailureReason, review: Bool) -> ShowerState {
        ShowerState(phase: .failed, machineID: "11223344", startedAt: t0,
                    failure: ShowerFailure(reason: reason, needsReview: review))
    }

    var records: [ShowerState] {
        [ShowerState(phase: .authorizing),
         ShowerState(phase: .running, startedAt: t0),
         ShowerState(phase: .settling, startedAt: t0),
         ShowerState(phase: .done, startedAt: t0),
         failed(.deviceUnavailable, review: false),
         failed(.authorizeRefused, review: false),
         failed(.deviceBusy, review: false),
         failed(.settleUncertain, review: true),
         ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive)]
    }

    /// Up and not running: no back button, no tab bar. Running (it collapses) or down: both show.
    func testOnlyRunningOrADownPageMayBeLeft() {
        let locked: Set<ShowerPagePhase> = [.connecting, .settling, .done, .connectFailed, .denied, .unsure, .needsCheck]
        for record in records {
            let phase = ShowerPage(record)!.phase
            XCTAssertEqual(ShowerPageFlow(record: record, presented: true).mayLeave, !locked.contains(phase), phase.rawValue)
            XCTAssertTrue(ShowerPageFlow(record: record, presented: false).mayLeave, phase.rawValue)
        }
        XCTAssertTrue(ShowerPageFlow(record: .idle, presented: false).mayLeave)
    }

    /// A start just tapped is connecting: the page holds the user at once.
    func testAStartJustTappedHoldsThePage() {
        let (flow, _) = ShowerPageFlow.reduce(ShowerPageFlow(record: .idle), .startTapped)
        XCTAssertEqual(flow.pushedPhase, .connecting)
        XCTAssertFalse(flow.mayLeave)
    }

    /// Up: the face of the record. Down: what still needs the user, never an answered result.
    func testPushedFace() {
        for record in records {
            let phase = ShowerPage(record)!.phase
            XCTAssertEqual(ShowerPageFlow(record: record, presented: true).pushedPhase, phase, phase.rawValue)
            let down: ShowerPagePhase? = [.done, .connectFailed, .denied].contains(phase) ? nil : phase
            XCTAssertEqual(ShowerPageFlow(record: record, presented: false).pushedPhase, down, phase.rawValue)
        }
        XCTAssertNil(ShowerPageFlow(record: .idle, presented: false).pushedPhase)
    }

    /// 去核对 leaves the check on the same page, which may now be left.
    func testReviewKeepsTheCheckButFreesThePage() {
        let check = ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive)
        let (flow, effects) = ShowerPageFlow.reduce(ShowerPageFlow(record: check, presented: true), .reviewTapped)
        XCTAssertEqual(effects, [.openReview])
        XCTAssertEqual(flow.pushedPhase, .needsCheck)
        XCTAssertTrue(flow.mayLeave)
    }

    /// The page down (after a relaunch or 先回首页): a record the user may mark checked still shows
    /// a face with 我在学校记录里核对过了 (unsure, needs-check).
    func testADownPageKeepsTheResolveFace() {
        let reasons: [ShowerFailureReason] = [.deviceUnavailable, .wrongDevice, .deviceBusy, .authorizeRefused,
                                              .authorizeUncertain, .authorizationInvalid, .closeUnconfirmed,
                                              .settleRefused, .settleUncertain, .settleUnconfirmed]
        var resolvable = reasons.map { failed($0, review: true) }
        resolvable.append(ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive))
        resolvable.append(ShowerState(phase: .writePending, startedAt: t0, stateReviewRequired: true))
        for record in resolvable {
            XCTAssertTrue(record.canResolveManually)
            let down = ShowerPageFlow(record: record, presented: false).pushedPhase
            XCTAssertTrue(down == .unsure || down == .needsCheck, "\(record.phase) \(String(describing: record.failure?.reason))")
        }
    }
}
