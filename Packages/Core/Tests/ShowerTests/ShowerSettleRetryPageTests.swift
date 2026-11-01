import XCTest
@testable import Core
import CoreTestSupport

/// 再结算一次 on the 不确定 face: offered only for a settlement that failed with its consumption
/// kept; the first tap arms it, the second sends it once more.
final class ShowerSettleRetryPageTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let consumption = HexCoding.upper(FakeFrames.identity("11223344", tail: 9))

    func failed(_ reason: ShowerFailureReason, review: Bool = true, consumption: String?) -> ShowerState {
        ShowerState(phase: .failed, machineID: "11223344", startedAt: t0, consumption: consumption,
                    failure: ShowerFailure(reason: reason, needsReview: review))
    }

    func reduce(_ flow: inout ShowerPageFlow, _ event: ShowerPageEvent) -> [ShowerPageEffect] {
        let (next, effects) = ShowerPageFlow.reduce(flow, event)
        flow = next
        return effects
    }

    func testRetryIsOfferedOnlyForASettlementThatFailedWithItsConsumption() {
        for reason in [ShowerFailureReason.settleRefused, .settleUncertain, .settleUnconfirmed] {
            let flow = ShowerPageFlow(record: failed(reason, consumption: consumption), presented: true)
            XCTAssertEqual(flow.page?.phase, .unsure)
            XCTAssertTrue(flow.mayRetrySettle, reason.rawValue)
            XCTAssertFalse(ShowerPageFlow(record: failed(reason, consumption: nil)).mayRetrySettle,
                           "\(reason.rawValue): nothing to settle")
        }
        for reason in [ShowerFailureReason.closeUnconfirmed, .authorizeUncertain, .authorizationInvalid] {
            XCTAssertFalse(ShowerPageFlow(record: failed(reason, consumption: consumption)).mayRetrySettle, reason.rawValue)
        }
        let others = [ShowerState(phase: .running, startedAt: t0), ShowerState(phase: .settling, startedAt: t0, consumption: consumption),
                      ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true), ShowerState(phase: .done, startedAt: t0)]
        for record in others {
            XCTAssertFalse(ShowerPageFlow(record: record).mayRetrySettle, "\(record.phase)")
        }
    }

    func testTheFirstTapArmsAndTheSecondSends() {
        let unsure = failed(.settleUncertain, consumption: consumption)
        var flow = ShowerPageFlow(record: unsure, presented: true)
        XCTAssertEqual(reduce(&flow, .settleRetryTapped), [.requestSettleRetry])
        XCTAssertFalse(flow.settleRetryArmed, "armed only once the record says so")

        let armed = ShowerReducer.reduce(unsure, .requestSettleRetry).0
        _ = reduce(&flow, .record(armed))
        XCTAssertTrue(flow.settleRetryArmed)
        XCTAssertEqual(reduce(&flow, .settleRetryTapped), [.confirmSettleRetry])

        var closed = ShowerPageFlow(record: failed(.closeUnconfirmed, consumption: nil), presented: true)
        XCTAssertEqual(reduce(&closed, .settleRetryTapped), [], "nothing to settle")
    }

    /// The retry runs through the engine: the settle goes out again only after the second tap.
    func testTheEngineSendsTheRetryOnlyAfterBothTaps() async throws {
        let store = InMemorySecureStore()
        let vault = StoredShowerVault(store: store)
        try vault.saveShowerState(failed(.settleUncertain, consumption: consumption))
        let gateway = FakeGateway()
        let engine = try ShowerEngine(transport: FakeShowerTransport(), gateway: gateway, vault: vault,
                                      configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
        var flow = ShowerPageFlow(record: await engine.state, presented: true)
        XCTAssertEqual(reduce(&flow, .settleRetryTapped), [.requestSettleRetry])
        _ = reduce(&flow, .record(try await engine.requestSettleRetry()))
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertEqual(reduce(&flow, .settleRetryTapped), [.confirmSettleRetry])
        gateway.scriptSettle(.ok(ShowerReceipt(amount: Money(fen: 163))))
        _ = reduce(&flow, .record(try await engine.confirmSettleRetry(binding)))
        XCTAssertEqual(gateway.settleFrames.count, 1)
        XCTAssertEqual(flow.page?.phase, .done)
        XCTAssertFalse(flow.mayRetrySettle)
    }
}

/// The unsure face says what became of the settlement it offers to send again.
final class ShowerSettleRetryCauseTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let frame = FakeFrames.identity("11223344", tail: 9)

    func cause(_ record: ShowerState) -> ShowerSettleRetryCause? { ShowerPageFlow(record: record, presented: true).settleRetryCause }

    var settling: ShowerState {
        ShowerState(phase: .settling, machineID: "11223344", startedAt: t0, consumption: HexCoding.upper(frame))
    }

    func testTheSchoolRefusedIt() {
        let refused = ShowerReducer.reduce(settling, .settleFailed(.rejected(.lxt6, code: "1", message: "x"))).0
        XCTAssertEqual(refused.failure?.reason, .settleRefused)
        XCTAssertEqual(cause(refused), .refused)
    }

    func testItWentOutWithNoAnswer() {
        XCTAssertEqual(cause(ShowerReducer.reduce(settling, .settleFailed(.uncertain(.lxt6))).0), .noAnswer)
        // The app stopped while it was settling: it may have left.
        XCTAssertEqual(cause(ShowerReducer.restore(settling)), .noAnswer)
    }

    func testItNeverLeft() {
        let cancelled = ShowerReducer.reduce(settling, .cancelledBeforeSend).0
        XCTAssertEqual(cancelled.failure?.reason, .settleUnconfirmed)
        XCTAssertEqual(cause(cancelled), .notSent)
        XCTAssertEqual(cause(ShowerReducer.restore(cancelled)), .notSent, "kept across a relaunch")
    }

    /// Held after an unconfirmed close found the water still running: never sent, but most
    /// likely someone else's water, so it is not the "just settle again" case.
    func testItWasHeldAsMaybeSomeoneElses() throws {
        var closing = ShowerState(phase: .closing, machineID: "11223344", startedAt: t0, authorizationID: "001122FF",
                                  closingFrom: .running, closeSent: true)
        closing.holdSettle = true
        let held = ShowerReducer.reduce(closing, .closeReplied(frame)).0
        XCTAssertEqual(cause(held), .held)
        XCTAssertEqual(cause(ShowerReducer.restore(held)), .held, "kept across a relaunch")
        let reread = try JSONDecoder().decode(ShowerState.self, from: JSONEncoder().encode(held))
        XCTAssertEqual(cause(reread), .held, "kept in the saved record")
    }

    func testNoCauseWithoutTheRetry() {
        let close = ShowerState(phase: .failed, machineID: "11223344", startedAt: t0,
                                failure: ShowerFailure(reason: .closeUnconfirmed, needsReview: true))
        XCTAssertNil(cause(close))
    }

    func testOlderRecordsReadAsNoAnswer() throws {
        let s = try JSONDecoder().decode(ShowerState.self, from: Data("""
        {"phase":"failed","machineID":"11223344","consumption":"\(HexCoding.upper(frame))","failure":{"reason":"settleUnconfirmed","needsReview":true}}
        """.utf8))
        XCTAssertEqual(cause(s), .noAnswer, "may have left")
    }
}
