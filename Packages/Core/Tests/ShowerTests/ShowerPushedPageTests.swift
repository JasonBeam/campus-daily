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

    /// Up and not running or stopped: no back button, no tab bar. Running or stopped (it collapses) or down: both show.
    func testOnlyRunningOrADownPageMayBeLeft() {
        let locked: Set<ShowerPagePhase> = [.connecting, .settling, .done, .connectFailed, .denied]
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

    /// The stopped page may be left; down, it still shows.
    func testTheStoppedPageMayBeLeftAndStillShows() {
        let stopped = ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive)
        XCTAssertTrue(ShowerPageFlow(record: stopped, presented: true).mayLeave)
        let (flow, effects) = ShowerPageFlow.reduce(ShowerPageFlow(record: stopped, presented: true), .collapseTapped)
        XCTAssertEqual(effects, [])
        XCTAssertEqual(flow.pushedPhase, .stopped)
        XCTAssertTrue(flow.mayLeave)
    }

    /// The page down (after a relaunch): a shower that is over still shows its face, whose one
    /// button is the next shower.
    func testADownPageKeepsTheStoppedFace() {
        let reasons: [ShowerFailureReason] = [.deviceUnavailable, .wrongDevice, .deviceBusy, .authorizeRefused,
                                              .authorizeUncertain, .authorizationInvalid, .closeUnconfirmed,
                                              .settleRefused, .settleUncertain, .settleUnconfirmed]
        var resolvable = reasons.map { failed($0, review: true) }
        resolvable.append(ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive))
        resolvable.append(ShowerState(phase: .writePending, startedAt: t0, stateReviewRequired: true))
        for record in resolvable {
            XCTAssertTrue(record.canResolveManually)
            let down = ShowerPageFlow(record: record, presented: false).pushedPhase
            XCTAssertEqual(down, .stopped, "\(record.phase) \(String(describing: record.failure?.reason))")
        }
    }

    /// The settled face's button sends the same answer as 好: the finished record is cleared and
    /// nothing starts; the page, still on the stack, shows the ready face and may be left.
    func testAnsweringTheSettledFaceShowsTheReadyFace() {
        let done = ShowerPageFlow(record: ShowerState(phase: .done, startedAt: t0), presented: true)
        let (flow, effects) = ShowerPageFlow.reduce(done, .closeTapped)
        XCTAssertEqual(effects, [.dismissRecord])
        XCTAssertFalse(effects.contains(.start))
        XCTAssertNil(flow.pushedPhase, "the ready face")
        XCTAssertTrue(flow.mayLeave)
        XCTAssertFalse(flow.starting)
    }
}

