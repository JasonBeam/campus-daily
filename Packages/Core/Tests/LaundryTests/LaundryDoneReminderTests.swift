//
//  LaundryDoneReminderTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import XCTest
import Foundation
@testable import Core

/// The 「衣服洗好了」 reminder: a fallback from the payment time while the machine hasn't
/// started, the exact end from a washing read, nothing once the order is over or failed.
final class LaundryDoneReminderTests: XCTestCase {
    typealias D = LaundryDoneReminder
    let t0 = L.t0

    func reduce(_ s: LaundryCheckout, _ e: LaundryEvent) -> LaundryCheckout { LaundryReducer.reduce(s, e).0 }

    /// Paid, seen at `at` by the verify poll.
    func paid(_ status: String = "20", remain: Int? = nil, at: Date) -> LaundryCheckout {
        var s = reduce(.empty, .confirm(L.draft, at: t0))
        s = reduce(s, .created(orderID: L.orderID))
        s = reduce(s, .orderRead(L.order("10"), at: t0.addingTimeInterval(1)))
        s = reduce(s, .paymentMethods([PayChannel(channel: "alipay")], at: t0.addingTimeInterval(2)))
        s = reduce(s, .returnedFromPayment)
        return reduce(s, .orderRead(L.order(status, remain: remain), at: at))
    }

    var seen: Date { t0.addingTimeInterval(60) }
    /// Payment seen + the 45-minute program.
    var fallback: D.Plan { D.Plan(orderID: L.orderID, end: seen.addingTimeInterval(45 * 60)) }

    func testPaidNotStartedRemindsAtPaymentPlusProgram() {
        let s = paid(at: seen)
        XCTAssertEqual(D.step(s, scheduled: nil, now: seen), .schedule(fallback))
    }

    func testExactEndReplacesTheFallback() {
        let read = seen.addingTimeInterval(300)
        let washing = reduce(paid(at: seen), .orderRead(L.order("40", remain: 50 * 60), at: read))
        let exact = D.Plan(orderID: L.orderID, end: read.addingTimeInterval(50 * 60))
        XCTAssertEqual(D.step(washing, scheduled: fallback, now: read), .schedule(exact))
        XCTAssertFalse(D.isScheduled(exact, as: fallback), "the fallback request is replaced")
        XCTAssertTrue(D.isScheduled(exact, as: exact))
        XCTAssertTrue(D.isScheduled(D.Plan(orderID: L.orderID, end: exact.end.addingTimeInterval(20)), as: exact),
                      "a re-read that moves the end a little keeps the request")
        XCTAssertFalse(D.isScheduled(D.Plan(orderID: "OTHER1", end: exact.end), as: exact))
    }

    func testUnconfirmedResultKeepsWhatIsSet() {
        let creating = reduce(.empty, .confirm(L.draft, at: t0))
        let reconcile = reduce(creating, .createFailed(.timedOut))
        for s in [creating, reconcile] {
            XCTAssertEqual(D.step(s, scheduled: fallback, now: seen), .keep)
        }
        // Paid, but no read since: the reminder stays.
        var unread = paid(at: seen)
        unread.phase = .verifying
        unread.order = nil
        XCTAssertEqual(D.step(unread, scheduled: fallback, now: seen), .keep)
    }

    func testFinishedOrCancelledOrderCancels() {
        let washing = reduce(paid(at: seen), .orderRead(L.order("40", remain: 600), at: seen))
        for status in ["50", "53"] {
            let over = reduce(washing, .orderRead(L.order(status), at: seen.addingTimeInterval(700)))
            XCTAssertEqual(over.phase, .none)
            XCTAssertEqual(D.step(over, scheduled: fallback, now: seen), .cancel, status)
        }
        XCTAssertEqual(D.step(nil, scheduled: fallback, now: seen), .cancel, "no machine set up")
    }

    /// Order 52: paid but the machine never ran, so the fallback must not say the clothes are done.
    func testFailedStartCancelsTheFallback() {
        let failed = reduce(paid(at: seen), .orderRead(L.order("52"), at: seen.addingTimeInterval(120)))
        XCTAssertEqual(failed.phase, .attention)
        XCTAssertEqual(D.step(failed, scheduled: fallback, now: seen.addingTimeInterval(120)), .cancel)
        let restored = LaundryReducer.restore(failed.persistable)
        XCTAssertEqual(D.step(restored, scheduled: fallback, now: seen.addingTimeInterval(120)), .cancel)
    }

    /// A request for this order is set already (after a relaunch, say): it stays as it is, and the
    /// app still knows it, so it can add it again after notifications are allowed again.
    func testAlreadySetRequestIsKeptAndKnown() {
        let s = paid(at: seen)
        XCTAssertEqual(D.step(s, scheduled: fallback, now: seen.addingTimeInterval(90)), .schedule(fallback))
        // An exact end set by an earlier washing read isn't moved back to the fallback.
        let exact = D.Plan(orderID: L.orderID, end: seen.addingTimeInterval(50 * 60))
        XCTAssertEqual(D.step(s, scheduled: exact, now: seen.addingTimeInterval(90)), .schedule(exact))
        XCTAssertTrue(D.isScheduled(exact, as: exact))
        // A request left from another order is replaced.
        let old = D.Plan(orderID: "OLDORDER1", end: seen)
        XCTAssertEqual(D.step(s, scheduled: old, now: seen.addingTimeInterval(90)), .schedule(fallback))
    }

    // MARK: The end stays where the remaining time was first read

    /// U净 can repeat a remaining time read after read: the end is the first read's + that time,
    /// not each read's, so it doesn't move later with every read.
    func testRepeatedReadOfTheSameRemainKeepsTheEnd() {
        let first = seen.addingTimeInterval(300)
        var s = reduce(paid(at: seen), .orderRead(L.order("40", remain: 600), at: first))
        for later in [60.0, 120, 400] {
            s = reduce(s, .orderRead(L.order("40", remain: 600), at: first.addingTimeInterval(later)))
            XCTAssertEqual(D.step(s, scheduled: nil, now: first.addingTimeInterval(later)),
                           .schedule(D.Plan(orderID: L.orderID, end: first.addingTimeInterval(600))), "read \(later) s later")
        }
    }

    /// A new remaining time anchors the end at the read that brought it.
    func testChangedRemainReanchors() {
        let first = seen.addingTimeInterval(300)
        var s = reduce(paid(at: seen), .orderRead(L.order("40", remain: 600), at: first))
        s = reduce(s, .orderRead(L.order("40", remain: 600), at: first.addingTimeInterval(60)))
        let moved = first.addingTimeInterval(130)
        s = reduce(s, .orderRead(L.order("40", remain: 480), at: moved))
        XCTAssertEqual(D.step(s, scheduled: nil, now: moved), .schedule(D.Plan(orderID: L.orderID, end: moved.addingTimeInterval(480))))
        s = reduce(s, .orderRead(L.order("40", remain: 480), at: moved.addingTimeInterval(90)))
        XCTAssertEqual(D.step(s, scheduled: nil, now: moved.addingTimeInterval(90)),
                       .schedule(D.Plan(orderID: L.orderID, end: moved.addingTimeInterval(480))), "and stays there while repeated")
    }

    /// Another status (paid, then washing) is a new reading even with the same number.
    func testStatusChangeReanchors() {
        let first = seen.addingTimeInterval(30)
        var s = reduce(paid(remain: 600, at: seen), .orderRead(L.order("20", remain: 600), at: first))
        let washing = first.addingTimeInterval(200)
        s = reduce(s, .orderRead(L.order("40", remain: 600), at: washing))
        XCTAssertEqual(D.step(s, scheduled: nil, now: washing), .schedule(D.Plan(orderID: L.orderID, end: washing.addingTimeInterval(600))))
    }

    /// Another order's read starts its own end, whatever the number left before.
    func testNewOrderResetsTheAnchor() {
        let first = seen.addingTimeInterval(300)
        let old = LaundryCheckout(phase: .active, orderID: L.orderID, order: L.order("40", id: "OLDORDER1", remain: 600),
                                  orderReadAt: first)
        let read = first.addingTimeInterval(120)
        let s = LaundryReducer.apply(L.order("40", remain: 600), at: read, to: old).0
        XCTAssertEqual(D.step(s, scheduled: nil, now: read), .schedule(D.Plan(orderID: L.orderID, end: read.addingTimeInterval(600))))
    }

    /// The anchor is kept with the record: after a relaunch a repeated read still keeps the end.
    func testTheAnchorSurvivesARelaunch() throws {
        let first = seen.addingTimeInterval(300)
        var s = reduce(paid(at: seen), .orderRead(L.order("40", remain: 600), at: first))
        s = reduce(s, .orderRead(L.order("40", remain: 600), at: first.addingTimeInterval(60)))
        let stored = try JSONDecoder().decode(LaundryCheckout.self, from: JSONEncoder().encode(s.persistable))
        var back = LaundryReducer.restore(stored)
        back = reduce(back, .orderRead(L.order("40", remain: 600), at: first.addingTimeInterval(200)))
        XCTAssertEqual(D.step(back, scheduled: nil, now: first.addingTimeInterval(200)),
                       .schedule(D.Plan(orderID: L.orderID, end: first.addingTimeInterval(600))))
    }
}
