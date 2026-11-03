import XCTest
@testable import Core
import CoreTestSupport

/// The first tap of 再结算一次 does not wait forever: leaving the page takes it back, so coming
/// back later never sends a settlement with one tap.
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
        for leave in [ShowerPageEvent.homeTapped, .reviewTapped] {
            let flow = ShowerPageFlow(record: armed, presented: true)
            XCTAssertTrue(flow.settleRetryArmed)
            let (left, effects) = ShowerPageFlow.reduce(flow, leave)
            XCTAssertFalse(left.presented)
            XCTAssertTrue(effects.contains(.disarmSettleRetry), "\(leave)")
        }
        // Not armed: nothing to take back.
        XCTAssertEqual(ShowerPageFlow.reduce(ShowerPageFlow(record: unsure, presented: true), .homeTapped).1, [])
        // Still on the page: the tap stays.
        XCTAssertFalse(ShowerPageFlow.reduce(ShowerPageFlow(record: armed, presented: true), .recheckTapped).1.contains(.disarmSettleRetry))
    }

    /// The page went away while the first tap was still on its way to the record: the armed
    /// record that comes in afterwards is taken back, and coming back needs two taps again.
    func testLeavingBeforeTheFirstTapLandsTakesItBack() async throws {
        let vault = StoredShowerVault(store: InMemorySecureStore())
        try vault.saveShowerState(unsure)
        let gateway = FakeGateway()
        let engine = try ShowerEngine(transport: FakeShowerTransport(), gateway: gateway, vault: vault,
                                      configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        var flow = ShowerPageFlow(record: unsure, presented: true)
        func send(_ event: ShowerPageEvent) -> [ShowerPageEffect] {
            let (next, effects) = ShowerPageFlow.reduce(flow, event)
            flow = next
            return effects
        }

        XCTAssertEqual(send(.settleRetryTapped), [.requestSettleRetry])
        XCTAssertEqual(send(.homeTapped), [], "nothing armed yet")
        let armedRecord = try await engine.requestSettleRetry()
        XCTAssertTrue(armedRecord.settleRetryArmed)
        XCTAssertEqual(send(.record(armedRecord)), [.disarmSettleRetry], "armed while the page is down")
        XCTAssertEqual(send(.record(armedRecord)), [], "taken back once")

        _ = send(.record(try await engine.disarmSettleRetry()))
        XCTAssertEqual(send(.reopen), [])
        XCTAssertTrue(flow.presented)
        XCTAssertFalse(flow.settleRetryArmed)
        XCTAssertEqual(send(.settleRetryTapped), [.requestSettleRetry], "the first tap only arms")
        XCTAssertTrue(gateway.settleFrames.isEmpty)

        // Armed with the page up: the tap stays.
        var shown = ShowerPageFlow(record: unsure, presented: true)
        let (next, effects) = ShowerPageFlow.reduce(shown, .record(armed))
        shown = next
        XCTAssertEqual(effects, [])
        XCTAssertTrue(shown.settleRetryArmed)
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
        XCTAssertEqual(ShowerPageFlow.reduce(ShowerPageFlow(record: disarmed, presented: true), .settleRetryTapped).1, [.requestSettleRetry])
    }

    // MARK: The pushed page (清爽)

    /// 清爽 pushes the page on 日常's stack: after 去核对, or reopened after a relaunch, it shows
    /// the unsure face with 再结算一次 while the flow is down. Visible, it holds the first tap like
    /// a page that is up, so the second tap can send.
    func testAVisiblePushedPageKeepsTheFirstTap() async throws {
        let vault = StoredShowerVault(store: InMemorySecureStore())
        try vault.saveShowerState(unsure)
        let gateway = FakeGateway()
        let engine = try ShowerEngine(transport: FakeShowerTransport(), gateway: gateway, vault: vault,
                                      configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        var flow = ShowerPageFlow(record: unsure, presented: false)
        func send(_ event: ShowerPageEvent) -> [ShowerPageEffect] {
            let (next, effects) = ShowerPageFlow.reduce(flow, event)
            flow = next
            return effects
        }

        XCTAssertEqual(send(.pushedAppeared), [])
        XCTAssertFalse(flow.presented, "the face stays the down one (resolve, no 先回首页)")
        XCTAssertTrue(flow.mayRetrySettle)
        XCTAssertEqual(send(.settleRetryTapped), [.requestSettleRetry])
        let armedRecord = try await engine.requestSettleRetry()
        XCTAssertEqual(send(.record(armedRecord)), [], "visible: the tap stays")
        XCTAssertTrue(flow.settleRetryArmed)
        XCTAssertEqual(send(.settleRetryTapped), [.confirmSettleRetry], "the second tap sends")
    }

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

    /// 去核对 or 先回首页 from a page that is up still takes the tap back, pushed or not.
    func testLeavingAnUpPageStillTakesItBackWhenPushed() {
        for leave in [ShowerPageEvent.homeTapped, .reviewTapped] {
            let flow = ShowerPageFlow.reduce(ShowerPageFlow(record: armed, presented: true), .pushedAppeared).0
            XCTAssertTrue(ShowerPageFlow.reduce(flow, leave).1.contains(.disarmSettleRetry), "\(leave)")
        }
    }
}
