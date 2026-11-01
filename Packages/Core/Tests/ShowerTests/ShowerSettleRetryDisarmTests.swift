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
}
