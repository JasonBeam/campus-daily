import XCTest
@testable import Core
import CoreTestSupport

/// A record an older build left with 再结算一次's first tap in (the app offers no settle retry
/// any more): leaving the page takes it back, so nothing is ever sent with one tap.
final class ShowerSettleRetryDisarmTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let consumption = HexCoding.upper(FakeFrames.identity("11223344", tail: 9))
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")

    var unsure: ShowerState {
        ShowerState(phase: .failed, machineID: "11223344", startedAt: t0, consumption: consumption,
                    failure: ShowerFailure(reason: .settleUncertain, needsReview: true))
    }
    var armed: ShowerState { ShowerReducer.reduce(unsure, .requestSettleRetry).0 }

    func testLeavingThePageTakesBackTheFirstTap() {
        let flow = ShowerPageFlow(record: armed, presented: true)
        XCTAssertEqual(flow.page?.phase, .stopped)
        let (left, effects) = ShowerPageFlow.reduce(flow, .collapseTapped)
        XCTAssertFalse(left.presented)
        XCTAssertEqual(effects, [.disarmSettleRetry])
        // Not armed: nothing to take back.
        XCTAssertEqual(ShowerPageFlow.reduce(ShowerPageFlow(record: unsure, presented: true), .collapseTapped).1, [])
        // Still on the page: the tap stays.
        XCTAssertFalse(ShowerPageFlow.reduce(ShowerPageFlow(record: armed, presented: true), .recheckTapped).1.contains(.disarmSettleRetry))
    }

    func testTheRecordForgetsTheFirstTap() {
        let (s, fx) = ShowerReducer.reduce(armed, .disarmSettleRetry)
        XCTAssertFalse(s.settleRetryArmed)
        XCTAssertEqual(fx, [])
        XCTAssertTrue(s.canRetrySettle, "the retry is still offered")
        XCTAssertEqual(ShowerReducer.reduce(unsure, .disarmSettleRetry).0, unsure)
    }

    func testAfterLeavingTheNextTapOnlyArmsAgain() async throws {
        let vault = StoredShowerVault(store: InMemorySecureStore())
        try vault.saveShowerState(unsure)
        let gateway = FakeGateway()
        let engine = try ShowerEngine(transport: FakeShowerTransport(), gateway: gateway, vault: vault,
                                      configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        _ = try await engine.requestSettleRetry()
        let disarmed = try await engine.disarmSettleRetry()
        XCTAssertFalse(disarmed.settleRetryArmed)
        XCTAssertEqual(try vault.showerState()?.settleRetryArmed, false, "persisted")
        do {
            _ = try await engine.confirmSettleRetry(binding)
            XCTFail("one tap must not send")
        } catch {
            XCTAssertEqual(error as? ShowerEngineError, .notAllowed)
        }
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    // MARK: The pushed page (清爽)

    /// Leaving the pushed page (popped, another page or tab over it) takes the tap back; so does
    /// a tap that lands once it has gone.
    func testLeavingThePushedPageTakesBackTheFirstTap() {
        var visible = ShowerPageFlow(record: armed, presented: false)
        visible = ShowerPageFlow.reduce(visible, .pushedAppeared).0
        XCTAssertTrue(visible.pushedVisible)
        let (left, effects) = ShowerPageFlow.reduce(visible, .pushedDisappeared)
        XCTAssertFalse(left.pushedVisible)
        XCTAssertEqual(effects, [.disarmSettleRetry])

        var gone = ShowerPageFlow(record: unsure, presented: false)
        gone = ShowerPageFlow.reduce(gone, .pushedAppeared).0
        gone = ShowerPageFlow.reduce(gone, .pushedDisappeared).0
        XCTAssertEqual(ShowerPageFlow.reduce(gone, .record(armed)).1, [.disarmSettleRetry])
        // Not armed: nothing to take back.
        XCTAssertEqual(ShowerPageFlow.reduce(ShowerPageFlow.reduce(ShowerPageFlow(record: unsure), .pushedAppeared).0,
                                             .pushedDisappeared).1, [])
    }

    /// Two copies on the stack (one under a page that must stay): the page counts as shown while
    /// any copy is, whatever order SwiftUI reports them in.
    func testThePushedPageIsShownWhileAnyCopyIs() {
        var flow = ShowerPageFlow(record: armed, presented: false)
        var effects: [ShowerPageEffect] = []
        for event in [ShowerPageEvent.pushedAppeared, .pushedAppeared, .pushedDisappeared] {
            let step = ShowerPageFlow.reduce(flow, event)
            flow = step.0; effects += step.1
        }
        XCTAssertTrue(flow.pushedVisible)
        XCTAssertEqual(effects, [])
        XCTAssertEqual(ShowerPageFlow.reduce(flow, .pushedDisappeared).1, [.disarmSettleRetry])
        XCTAssertEqual(ShowerPageFlow.reduce(ShowerPageFlow(record: armed), .pushedDisappeared).0.pushedVisible, false,
                       "never below none")
    }

    /// A page that is up and collapses still takes the tap back, pushed or not.
    func testLeavingAnUpPageStillTakesItBackWhenPushed() {
        let flow = ShowerPageFlow.reduce(ShowerPageFlow(record: armed, presented: true), .pushedAppeared).0
        XCTAssertTrue(ShowerPageFlow.reduce(flow, .collapseTapped).1.contains(.disarmSettleRetry))
    }
}
