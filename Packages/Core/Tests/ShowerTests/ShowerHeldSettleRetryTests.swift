import XCTest
@testable import Core
import CoreTestSupport

/// A settlement an older build held back (the water it read might not have been ours) is never
/// sent by this one: not by the retry, not from a relaunch. Retries of other settlements keep
/// their own cause.
final class ShowerHeldSettleRetryTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let frame = FakeFrames.identity("11223344", tail: 9)

    /// What the record says became of the settlement (the page no longer words it).
    enum Cause { case refused, notSent, noAnswer }
    func cause(_ record: ShowerState) -> Cause? {
        guard record.canRetrySettle, let failure = record.failure else { return nil }
        if failure.reason == .settleRefused { return .refused }
        return failure.settleNotSent ? .notSent : .noAnswer
    }

    /// As an older build saved it.
    var held: ShowerState {
        ShowerState(phase: .failed, machineID: "11223344", startedAt: t0, authorizationID: "001122FF", closeSent: true,
                    consumption: HexCoding.upper(frame),
                    failure: ShowerFailure(reason: .settleUnconfirmed, needsReview: true, settleNotSent: true, settleHeld: true),
                    heldConsumption: HexCoding.upper(frame))
    }

    /// The two taps of 再结算一次.
    func retrying(_ s: ShowerState) -> ShowerState {
        let armed = ShowerReducer.reduce(s, .requestSettleRetry).0
        let (settling, fx) = ShowerReducer.reduce(armed, .confirmSettleRetry)
        XCTAssertEqual(settling.phase, .settling)
        XCTAssertTrue(fx.contains(.settle(frame: frame)))
        return settling
    }

    func testAHeldSettlementIsNeverRetried() throws {
        // An older build's failed retry of it, too.
        var refusedRetry = held
        refusedRetry.failure = ShowerFailure(reason: .settleRefused, needsReview: true, error: .rejected(.lxt6, code: "1", message: "x"),
                                             settleHeld: true)
        for record in [held, refusedRetry, ShowerReducer.restore(held)] {
            XCTAssertNil(cause(record))
            let (armed, fx) = ShowerReducer.reduce(record, .requestSettleRetry)
            XCTAssertFalse(armed.settleRetryArmed)
            XCTAssertEqual(fx, [])
            var forced = record; forced.settleRetryArmed = true
            XCTAssertEqual(ShowerReducer.reduce(forced, .confirmSettleRetry).1, [])
            let reread = try JSONDecoder().decode(ShowerState.self, from: JSONEncoder().encode(record))
            XCTAssertNil(cause(reread))
        }
        // The app stopped while an older build's retry of it was out: kept, and still not retried.
        var settling = held; settling.phase = .settling; settling.failure = nil
        let restored = ShowerReducer.restore(settling)
        XCTAssertEqual(restored.failure?.reason, .settleUnconfirmed)
        XCTAssertEqual(restored.failure?.settleHeld, true)
        XCTAssertNil(cause(restored))
    }

    func testARetryThatIsNotHeldKeepsItsOwnCause() {
        let settling = ShowerState(phase: .settling, machineID: "11223344", startedAt: t0, consumption: HexCoding.upper(frame))
        let noAnswer = ShowerReducer.reduce(settling, .settleFailed(.uncertain(.lxt6))).0
        XCTAssertEqual(cause(noAnswer), .noAnswer)
        let refused = ShowerReducer.reduce(retrying(noAnswer), .settleFailed(.rejected(.lxt6, code: "1", message: "x"))).0
        XCTAssertEqual(cause(refused), .refused)
    }
}
