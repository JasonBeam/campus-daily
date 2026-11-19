import XCTest
import Foundation
@testable import Core

/// When the app reads the open order while it is in front: the cadence, what stops it, the wait
/// after a failed read, and what the polling task is rebuilt on.
final class LaundryForegroundPollTests: XCTestCase {
    typealias P = LaundryForegroundPoll
    let t0 = L.t0

    /// 立刻洗衣, confirmed at `t0`, paid (20), no start tried.
    func paid(immediate: Bool = true, start: LaundryStart? = nil, status: String = "20", remain: Int? = nil,
              phase: LaundryPhase = .active) -> LaundryCheckout {
        LaundryCheckout(phase: phase, draft: L.draft, createdAt: t0, orderID: L.orderID, order: L.order(status, remain: remain),
                        orderReadAt: t0.addingTimeInterval(20), accountID: "acct-1", paidAt: t0.addingTimeInterval(20),
                        immediate: immediate, start: start)
    }

    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testIntervalsFollowTheCadence() {
        let front = at(30)
        let poll = P(frontSince: front)
        let c = paid()
        XCTAssertEqual(poll.interval(c, remindersOn: false, now: front), 1)
        XCTAssertEqual(poll.interval(c, remindersOn: false, now: front.addingTimeInterval(19.9)), 1)
        XCTAssertEqual(poll.interval(c, remindersOn: false, now: front.addingTimeInterval(20)), 3, "after 20 s in front")
        XCTAssertEqual(poll.interval(c, remindersOn: false, now: at(600)), 3, "the window's last second")
        XCTAssertNil(poll.interval(c, remindersOn: false, now: at(600.5)), "past the window, reminders off")
        XCTAssertEqual(poll.interval(c, remindersOn: true, now: at(601)), 30, "past the window, reminders on")
        // A later return to the front starts the fast period again.
        XCTAssertEqual(P(frontSince: at(300)).interval(c, remindersOn: false, now: at(301)), 1)
    }

    /// The payment check (back from Alipay, or restored after a relaunch) is read on the fast
    /// cadence with the reminder off, so a failed read doesn't end it.
    func testAnOrderBeingCheckedNeedsItsStartToo() {
        let checking = paid(phase: .verifying)
        XCTAssertTrue(P.needsStart(checking, now: at(60)))
        XCTAssertEqual(P(frontSince: at(60)).interval(checking, remindersOn: false, now: at(60)), 1)
        XCTAssertTrue(P(frontSince: at(60)).isDue(checking, remindersOn: false, now: at(60)))
    }

    func testFastReadsStopOnceTriedBlockedWashingOrDone() {
        let now = at(60)
        let tried: [LaundryStart] = [.sent(at: now), .accepted(at: now), .pending(at: now), .refused(message: "", at: now),
                                     .blocked(.expired), .blocked(.price), .blocked(.unsupported), .started]
        for start in tried {
            XCTAssertFalse(P.needsStart(paid(start: start), now: now), "\(start)")
        }
        XCTAssertFalse(P.needsStart(paid(status: "40", remain: 1800), now: now), "washing")
        XCTAssertFalse(P.needsStart(paid(phase: .paying), now: now), "Alipay still open: coming back reads it")
        XCTAssertFalse(P.needsStart(paid(phase: .created), now: now), "not paid")
        XCTAssertFalse(P.needsStart(paid(phase: .attention), now: now))
        XCTAssertFalse(P.needsStart(.empty, now: now))
        XCTAssertFalse(P.needsStart(nil, now: now))
        var future = paid()
        future.createdAt = at(120)
        XCTAssertFalse(P.needsStart(future, now: now), "a confirmation time in the future is outside the window")
        var unknown = paid()
        unknown.createdAt = nil
        XCTAssertFalse(P.needsStart(unknown, now: now))
    }

    /// Any other open order is read every 30 s while the done reminder is on, and not at all
    /// while it is off.
    func testRemindersReadEvery30Seconds() {
        let poll = P(frontSince: at(60))
        for c in [paid(immediate: false), paid(start: .accepted(at: at(30))), paid(status: "40", remain: 1800),
                  paid(immediate: false, phase: .created), paid(immediate: false, phase: .verifying)] {
            XCTAssertEqual(poll.interval(c, remindersOn: true, now: at(61)), 30)
            XCTAssertNil(poll.interval(c, remindersOn: false, now: at(61)))
        }
        for c in [LaundryCheckout.empty, paid(phase: .attention), paid(phase: .reconcile), paid(phase: .cancelling)] {
            XCTAssertNil(poll.interval(c, remindersOn: true, now: at(61)), "\(c.phase)")
        }
        XCTAssertNil(poll.interval(nil, remindersOn: true, now: at(61)))
        // Coming to the front reads the order already: the first reminder read waits an interval.
        let c = paid(immediate: false)
        XCTAssertFalse(poll.isDue(c, remindersOn: true, now: at(61)))
        XCTAssertFalse(poll.isDue(c, remindersOn: true, now: at(89.9)))
        XCTAssertTrue(poll.isDue(c, remindersOn: true, now: at(90)))
    }

    /// A normal order is never started, however often it is read.
    func testNormalOrdersAreNeverStarted() {
        let normal = paid(immediate: false)
        XCTAssertFalse(P.needsStart(normal, now: at(30)))
        var s = normal
        for second in 0..<600 {
            let (next, effects) = LaundryReducer.reduce(s, .refresh)
            XCTAssertEqual(effects, [.readOrder(id: L.orderID, after: 0)])
            s = LaundryReducer.reduce(next, .orderRead(L.order("20"), at: at(TimeInterval(30 + second)))).0
        }
        XCTAssertNil(s.start)
    }

    func testTheFirstStartReadIsAtOnceThenEverySecond() {
        var poll = P(frontSince: at(30))
        let c = paid()
        XCTAssertTrue(poll.isDue(c, remindersOn: false, now: at(30)))
        poll.record(.read, at: at(30))
        XCTAssertFalse(poll.isDue(c, remindersOn: false, now: at(30.5)))
        XCTAssertTrue(poll.isDue(c, remindersOn: false, now: at(31)))
        poll.record(.read, at: at(55))
        XCTAssertFalse(poll.isDue(c, remindersOn: false, now: at(57)), "3 s after the first 20")
        XCTAssertTrue(poll.isDue(c, remindersOn: false, now: at(58)))
    }

    /// A failed read waits 30 s on its own clock: the 1-second cadence, a changed record or a
    /// skipped tick don't bring the next read forward.
    func testAFailedReadWaits30Seconds() {
        var poll = P(frontSince: at(30))
        var c = paid()
        poll.record(.failed, at: at(31))
        for second in stride(from: 31.0, to: 61.0, by: 0.5) {
            XCTAssertFalse(poll.isDue(c, remindersOn: true, now: at(second)), "\(second)")
        }
        // The record changes (another read, the notice going) while waiting: still waiting.
        c.notice = nil
        c.orderReadAt = at(40)
        c.checkingStart = true
        XCTAssertFalse(poll.isDue(c, remindersOn: true, now: at(45)))
        poll.record(.skipped, at: at(50))
        XCTAssertFalse(poll.isDue(c, remindersOn: true, now: at(55)), "a skip doesn't end the wait")
        XCTAssertTrue(poll.isDue(c, remindersOn: true, now: at(61)))
        // A read that goes through ends it.
        poll.record(.read, at: at(61))
        XCTAssertNil(poll.failedAt)
        XCTAssertTrue(poll.isDue(c, remindersOn: true, now: at(64)))
        // A reminder read fails too: 30 s, not less.
        var regular = P(frontSince: at(0))
        let normal = paid(immediate: false)
        regular.record(.failed, at: at(100))
        XCTAssertFalse(regular.isDue(normal, remindersOn: true, now: at(129)))
        XCTAssertTrue(regular.isDue(normal, remindersOn: true, now: at(130)))
    }

    /// A tick skipped because a step was running is not a read: the next tick reads.
    func testASkippedReadIsNotARead() {
        var poll = P(frontSince: at(30))
        let c = paid()
        poll.record(.read, at: at(30))
        poll.record(.skipped, at: at(31))
        XCTAssertNil(poll.failedAt)
        XCTAssertEqual(poll.lastRead, at(30))
        XCTAssertTrue(poll.isDue(c, remindersOn: false, now: at(31)))
    }

    func testOutcomes() {
        XCTAssertEqual(P.Outcome(notice: nil), .read)
        XCTAssertEqual(P.Outcome(notice: .paymentNotConfirmed), .read)
        XCTAssertEqual(P.Outcome(notice: .cancelNotAllowed), .read)
        XCTAssertEqual(P.Outcome(notice: .readFailed(.offline)), .failed)
        XCTAssertEqual(P.Outcome(notice: .readFailed(.timedOut)), .failed)
        XCTAssertEqual(P.Outcome(notice: .refused(.rejected(.ujing, code: "500", message: "x"))), .failed)
        XCTAssertEqual(P.Outcome(notice: .sessionExpired), .failed)
        XCTAssertEqual(P.Outcome(notice: .orderMismatch), .failed)
        XCTAssertEqual(P.Outcome(error: LaundryEngineError.busy), .skipped)
        XCTAssertEqual(P.Outcome(error: LaundryEngineError.storage), .failed)
        XCTAssertEqual(P.Outcome(error: ServiceError.offline), .failed)
    }

    /// The task is rebuilt only for the front, the engine and the order: never for the start
    /// record, the pre-start read or a step running, which change while the task's own read runs.
    func testTheTaskIdentityIgnoresTheStart() {
        let base = paid()
        let id = P.Identity(inFront: true, engine: 1, record: base)
        var changes: [LaundryCheckout] = []
        for start in [LaundryStart.sent(at: at(30)), .accepted(at: at(30)), .pending(at: at(30)), .blocked(.expired), .started] {
            var c = base; c.start = start; changes.append(c)
        }
        var checking = base; checking.checkingStart = true; changes.append(checking)
        var noticed = base; noticed.notice = .readFailed(.offline); changes.append(noticed)
        var polled = base; polled.startPollAttempt = 2; changes.append(polled)
        var read = base; read.order = L.order("40", remain: 1800); read.orderReadAt = at(90); changes.append(read)
        var checkingPay = base; checkingPay.phase = .verifying; changes.append(checkingPay)
        for c in changes {
            XCTAssertEqual(P.Identity(inFront: true, engine: 1, record: c), id)
        }
        // The create gives the order its id: the same order.
        var creating = base; creating.phase = .creating; creating.orderID = nil
        XCTAssertEqual(P.Identity(inFront: true, engine: 1, record: creating), id)

        XCTAssertNotEqual(P.Identity(inFront: false, engine: 1, record: base), id)
        XCTAssertNotEqual(P.Identity(inFront: true, engine: 2, record: base), id)
        var other = base; other.createdAt = at(700)
        XCTAssertNotEqual(P.Identity(inFront: true, engine: 1, record: other), id)
        XCTAssertNotEqual(P.Identity(inFront: true, engine: 1, record: .empty), id)
        XCTAssertEqual(P.Identity(inFront: true, engine: 1, record: .empty), P.Identity(inFront: true, engine: 1, record: nil))
    }
}
