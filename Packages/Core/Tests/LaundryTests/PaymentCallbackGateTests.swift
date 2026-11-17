import XCTest
@testable import Core

/// One payment attempt at a time: an SDK callback reaches only the attempt it was made for, at
/// most once; one that comes before the interceptor decides waits for the decision.
final class PaymentCallbackGateTests: XCTestCase {
    func testEarlyCallbackBufferedThenDeliveredOnTakeover() {
        var gate = PaymentCallbackGate()
        let a = gate.begin(takenOver: false)
        XCTAssertEqual(gate.receive(a), .buffered)
        XCTAssertTrue(gate.resolve(a, takenOver: true), "the buffered callback goes out now")
        XCTAssertEqual(gate.receive(a), .droppedLate, "and only once")
    }

    func testEarlyCallbackDroppedOnDecline() {
        var gate = PaymentCallbackGate()
        let a = gate.begin(takenOver: false)
        XCTAssertEqual(gate.receive(a), .buffered)
        XCTAssertFalse(gate.resolve(a, takenOver: false))
        XCTAssertEqual(gate.state, .declined)
    }

    func testLateCallbackAfterDeclineDropped() {
        var gate = PaymentCallbackGate()
        let a = gate.begin(takenOver: false)
        XCTAssertFalse(gate.resolve(a, takenOver: false))
        XCTAssertEqual(gate.receive(a), .droppedLate)
    }

    func testTakeoverWithoutEarlyCallbackDeliversTheNextOne() {
        var gate = PaymentCallbackGate()
        let a = gate.begin(takenOver: false)
        XCTAssertFalse(gate.resolve(a, takenOver: true), "nothing buffered")
        XCTAssertEqual(gate.receive(a), .deliver)
    }

    func testDeliveredOnlyOnce() {
        var gate = PaymentCallbackGate()
        let a = gate.begin(takenOver: true)
        XCTAssertEqual(gate.receive(a), .deliver)
        XCTAssertEqual(gate.receive(a), .droppedLate)
        XCTAssertEqual(gate.state, .delivered)
    }

    func testOnlyFirstEarlyCallbackBuffered() {
        var gate = PaymentCallbackGate()
        let a = gate.begin(takenOver: false)
        XCTAssertEqual(gate.receive(a), .buffered)
        XCTAssertEqual(gate.receive(a), .droppedLate)
        XCTAssertTrue(gate.resolve(a, takenOver: true))
        XCTAssertEqual(gate.receive(a), .droppedLate)
    }

    /// A's callback made before B began never reaches B, and doesn't use up B's one callback.
    func testOldAttemptCallbackDroppedAfterNewBegin() {
        var gate = PaymentCallbackGate()
        let a = gate.begin(takenOver: true)
        let b = gate.begin(takenOver: true)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(gate.receive(a), .droppedStale)
        XCTAssertEqual(gate.receive(b), .deliver)
    }

    /// A's interceptor deciding after B began changes nothing for B.
    func testOldAttemptResolveIgnored() {
        var gate = PaymentCallbackGate()
        let a = gate.begin(takenOver: false)
        _ = gate.receive(a)
        let b = gate.begin(takenOver: false)
        XCTAssertFalse(gate.resolve(a, takenOver: true))
        XCTAssertEqual(gate.state, .pending)
        XCTAssertEqual(gate.receive(b), .buffered)
    }

    func testUnknownAttemptDropped() {
        var gate = PaymentCallbackGate()
        XCTAssertEqual(gate.receive(UUID()), .droppedStale)
        _ = gate.begin(takenOver: true)
        XCTAssertEqual(gate.receive(UUID()), .droppedStale)
        XCTAssertFalse(gate.resolve(UUID(), takenOver: true))
    }

    /// A safepay return URL can't say whose it is: passed to the SDK only while the current
    /// attempt went to it, and it never uses up that attempt's callback.
    func testSafepayReturnOnlyForTakenOverCurrent() {
        var gate = PaymentCallbackGate()
        XCTAssertFalse(gate.acceptsReturnURL)
        let a = gate.begin(takenOver: false)
        XCTAssertFalse(gate.acceptsReturnURL, "undecided")
        _ = gate.resolve(a, takenOver: false)
        XCTAssertFalse(gate.acceptsReturnURL, "declined: the link opened outside")
        let b = gate.begin(takenOver: true)
        XCTAssertTrue(gate.acceptsReturnURL)
        XCTAssertEqual(gate.state, .takenOver, "a URL changes nothing")
        XCTAssertEqual(gate.receive(b), .deliver)
        XCTAssertTrue(gate.acceptsReturnURL, "the SDK may still finish its own return")
    }
}
