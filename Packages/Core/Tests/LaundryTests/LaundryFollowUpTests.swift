import XCTest
import Foundation
@testable import Core

/// A paid order that is not washing yet (20, starting, or 40 without a remaining time) is read
/// again for a few minutes, and the done reminder has a time before the washing read arrives.
final class LaundryFollowUpTests: XCTestCase {
    typealias R = LaundryReducer
    typealias F = LaundryFollowUp
    let t0 = L.t0

    func reduce(_ s: LaundryCheckout, _ e: LaundryEvent) -> LaundryCheckout { R.reduce(s, e).0 }

    /// Paid, seen at `at` by the verify poll.
    func paid(_ status: String = "20", remain: Int? = nil, at: Date) -> LaundryCheckout {
        var s = reduce(.empty, .confirm(L.draft, at: t0))
        s = reduce(s, .created(orderID: L.orderID))
        s = reduce(s, .orderRead(L.order("10"), at: t0.addingTimeInterval(1)))
        s = reduce(s, .paymentMethods([PayChannel(channel: "alipay")], at: t0.addingTimeInterval(2)))
        s = reduce(s, .returnedFromPayment)
        return reduce(s, .orderRead(L.order(status, remain: remain), at: at))
    }

    func testPaidButNotWashingIsReadAgainForAFewMinutes() {
        let seen = t0.addingTimeInterval(60)
        var s = paid(at: seen)
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(F.nextRead(s, lastAttempt: nil, now: seen), F.interval)
        XCTAssertEqual(F.nextRead(s, lastAttempt: nil, now: seen.addingTimeInterval(20)), F.interval - 20)
        XCTAssertEqual(F.nextRead(s, lastAttempt: nil, now: seen.addingTimeInterval(90)), 0, "overdue: read now")

        // Still 20 on every read: the reads stop once the window is used up.
        var reads = 0
        var now = seen
        while let delay = F.nextRead(s, lastAttempt: nil, now: now) {
            now = now.addingTimeInterval(delay)
            s = reduce(s, .orderRead(L.order("20"), at: now))
            reads += 1
            XCTAssertLessThan(reads, 20)
        }
        XCTAssertGreaterThanOrEqual(reads, 4)
        XCTAssertLessThanOrEqual(now.timeIntervalSince(seen), F.window)
        XCTAssertGreaterThanOrEqual(F.interval, 30)
        XCTAssertLessThanOrEqual(F.interval, 60)
    }

    func testAFailedAttemptWaitsAFullInterval() {
        let seen = t0.addingTimeInterval(60)
        let s = paid(at: seen)
        let attempt = seen.addingTimeInterval(F.interval)
        XCTAssertEqual(F.nextRead(s, lastAttempt: attempt, now: attempt), F.interval)
    }

    func testWashingWithATimeStopsTheReads() {
        let seen = t0.addingTimeInterval(60)
        let washing = reduce(paid(at: seen), .orderRead(L.order("40", remain: 2400), at: seen.addingTimeInterval(45)))
        XCTAssertNil(F.nextRead(washing, lastAttempt: nil, now: seen.addingTimeInterval(50)))
        XCTAssertNil(F.nextRead(paid("40", remain: 2400, at: seen), lastAttempt: nil, now: seen))
    }

    func testWashingWithoutATimeIsReadAgain() {
        let seen = t0.addingTimeInterval(60)
        let washing = reduce(paid(at: seen), .orderRead(L.order("40", remain: 2400), at: seen.addingTimeInterval(45)))
        // At the end of the wash U净 may still say 40 with nothing left: read until it says 50.
        let end = seen.addingTimeInterval(45 + 2460)
        let noTime = reduce(washing, .orderRead(L.order("40", remain: 0), at: end))
        XCTAssertEqual(F.nextRead(noTime, lastAttempt: nil, now: end), F.interval)
        let done = reduce(noTime, .orderRead(L.order("50"), at: end.addingTimeInterval(F.interval)))
        XCTAssertNil(F.nextRead(done, lastAttempt: nil, now: end.addingTimeInterval(F.interval)))
    }

    func testOnlyPaidOrdersAreFollowed() {
        var s = reduce(.empty, .confirm(L.draft, at: t0))
        XCTAssertNil(F.nextRead(s, lastAttempt: nil, now: t0))
        s = reduce(reduce(s, .created(orderID: L.orderID)), .orderRead(L.order("10"), at: t0))
        XCTAssertNil(F.nextRead(s, lastAttempt: nil, now: t0))
        XCTAssertNil(F.expectedEnd(s))
    }

    func testDoneReminderFallsBackToPaymentTimePlusProgram() {
        let seen = t0.addingTimeInterval(60)
        let s = paid(at: seen)
        XCTAssertEqual(F.expectedEnd(s), seen.addingTimeInterval(45 * 60))
        // Later reads keep the time the payment was first seen.
        let later = reduce(s, .orderRead(L.order("20"), at: seen.addingTimeInterval(45)))
        XCTAssertEqual(F.expectedEnd(later), seen.addingTimeInterval(45 * 60))
        XCTAssertEqual(R.restore(later.persistable).paidAt, seen)
        XCTAssertNil(F.expectedEnd(reduce(later, .orderRead(L.order("50"), at: seen.addingTimeInterval(90)))))
    }
}
