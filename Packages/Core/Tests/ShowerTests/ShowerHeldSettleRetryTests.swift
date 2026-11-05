import XCTest
@testable import Core
import CoreTestSupport

/// A held settlement (the water it read may be someone else's) stays held when its retry is
/// refused or gets no answer: the record still says so, and does not read as the
/// plain "settle again" case.
final class ShowerHeldSettleRetryTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let frame = FakeFrames.identity("11223344", tail: 9)

    /// What the record says became of the settlement (the page no longer words it).
    enum Cause { case held, refused, notSent, noAnswer }
    func cause(_ record: ShowerState) -> Cause? {
        guard record.canRetrySettle, let failure = record.failure else { return nil }
        if failure.settleHeld { return .held }
        if failure.reason == .settleRefused { return .refused }
        return failure.settleNotSent ? .notSent : .noAnswer
    }

    var held: ShowerState {
        var closing = ShowerState(phase: .closing, machineID: "11223344", startedAt: t0, authorizationID: "001122FF",
                                  closingFrom: .running, closeSent: true)
        closing.holdSettle = true
        return ShowerReducer.reduce(closing, .closeReplied(frame)).0
    }

    /// The two taps of 再结算一次: the held frame goes out.
    func retrying(_ s: ShowerState) -> ShowerState {
        let armed = ShowerReducer.reduce(s, .requestSettleRetry).0
        let (settling, fx) = ShowerReducer.reduce(armed, .confirmSettleRetry)
        XCTAssertEqual(settling.phase, .settling)
        XCTAssertTrue(fx.contains(.settle(frame: frame)))
        return settling
    }

    func testARefusedOrUnansweredRetryOfAHeldSettlementIsStillHeld() throws {
        XCTAssertEqual(cause(held), .held)
        let outcomes: [(ShowerEvent, ShowerFailureReason)] = [
            (.settleFailed(.rejected(.lxt6, code: "1", message: "x")), .settleRefused),
            (.settleFailed(.uncertain(.lxt6)), .settleUncertain),
            (.settleFailed(.timedOut), .settleUncertain),
            (.cancelledBeforeSend, .settleUnconfirmed),
        ]
        for (event, reason) in outcomes {
            let after = ShowerReducer.reduce(retrying(held), event).0
            XCTAssertEqual(after.failure?.reason, reason, "\(event)")
            XCTAssertEqual(cause(after), .held, "\(event)")
            XCTAssertEqual(cause(ShowerReducer.restore(after)), .held, "kept across a relaunch (\(event))")
            let reread = try JSONDecoder().decode(ShowerState.self, from: JSONEncoder().encode(after))
            XCTAssertEqual(cause(reread), .held, "kept in the saved record (\(event))")
            // And again after a second retry.
            let again = ShowerReducer.reduce(retrying(after), .settleFailed(.uncertain(.lxt6))).0
            XCTAssertEqual(cause(again), .held, "\(event), twice")
        }
        // The app stopped while the retry was out.
        XCTAssertEqual(cause(ShowerReducer.restore(retrying(held))), .held, "relaunch mid-retry")
    }

    func testARetryThatIsNotHeldKeepsItsOwnCause() {
        let settling = ShowerState(phase: .settling, machineID: "11223344", startedAt: t0, consumption: HexCoding.upper(frame))
        let noAnswer = ShowerReducer.reduce(settling, .settleFailed(.uncertain(.lxt6))).0
        XCTAssertEqual(cause(noAnswer), .noAnswer)
        let refused = ShowerReducer.reduce(retrying(noAnswer), .settleFailed(.rejected(.lxt6, code: "1", message: "x"))).0
        XCTAssertEqual(cause(refused), .refused)
    }
}
