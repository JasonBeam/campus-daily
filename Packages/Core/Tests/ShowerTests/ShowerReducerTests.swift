import XCTest
import Foundation
import Core
import CoreTestSupport

/// Architecture §3.1 transitions, one by one, on the pure reducer.
final class ShowerReducerTests: XCTestCase {
    let machine = "11223344"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
    var consumption: Data { FakeFrames.identity(machine, tail: 9) }
    var auth: ShowerAuthorization { ShowerAuthorization(machineID: machine, payload: Data(count: 15), authorizationID: "001122ff") }

    func reduce(_ s: ShowerState, _ e: ShowerEvent) -> (ShowerState, [ShowerEffect]) { ShowerReducer.reduce(s, e) }

    func authorizing() -> ShowerState {
        let (s, _) = reduce(.idle, .start(machineID: "11223344", preferredPeripheral: nil))
        let (s2, _) = reduce(s, .connected(peripheralID: "P", probe: identity))
        return s2
    }

    func running() -> ShowerState {
        let (s, _) = reduce(authorizing(), .authorized(auth, at: t0))
        return reduce(s, .writeReplied(FakeFrames.ack)).0
    }

    func settling() -> ShowerState {
        let (c, _) = reduce(running(), .finish)
        let (c2, _) = reduce(c, .probeReplied(FakeFrames.active))
        return reduce(c2, .closeReplied(consumption)).0
    }

    // MARK: start

    func testStartConnectsAndProbesBeforeAnythingIsSent() {
        let (s, fx) = reduce(.idle, .start(machineID: "1a2b3c4d", preferredPeripheral: "P"))
        XCTAssertEqual(s.phase, .authorizing)
        XCTAssertEqual(s.machineID, "1A2B3C4D")
        XCTAssertFalse(s.authorizeSent)
        XCTAssertNil(s.startedAt, "connecting is not shower time")
        XCTAssertEqual(fx, [.connectAndProbe(machineID: "1A2B3C4D", preferred: "P")])
    }

    func testIdleIdentityMarksAuthorizeSentAndPostsTheFrame() {
        let (s, _) = reduce(.idle, .start(machineID: machine, preferredPeripheral: nil))
        let (s2, fx) = reduce(s, .connected(peripheralID: "P", probe: identity))
        XCTAssertTrue(s2.authorizeSent)
        XCTAssertEqual(s2.peripheralID, "P")
        XCTAssertEqual(fx, [.authorize(frame: identity)])
    }

    func testProbeProblemsFailWithoutReviewAndNothingSent() {
        let (s, _) = reduce(.idle, .start(machineID: machine, preferredPeripheral: nil))
        let cases: [(ShowerEvent, ShowerFailureReason)] = [
            (.connected(peripheralID: "P", probe: FakeFrames.identity("99999999")), .wrongDevice),
            (.connected(peripheralID: "P", probe: FakeFrames.active), .deviceBusy),
            (.connected(peripheralID: "P", probe: Data([0x00])), .deviceUnavailable),
            (.connectFailed(.notFound), .deviceUnavailable),
            (.connectFailed(.bluetoothOff), .deviceUnavailable),
        ]
        for (event, reason) in cases {
            let (f, fx) = reduce(s, event)
            XCTAssertEqual(f.phase, .failed, "\(event)")
            XCTAssertEqual(f.failure?.reason, reason, "\(event)")
            XCTAssertEqual(f.failure?.needsReview, false)
            XCTAssertFalse(f.authorizeSent)
            XCTAssertEqual(fx, [.releaseDevice])
            XCTAssertTrue(f.canStart)
            XCTAssertEqual(f.persistable.phase, .idle, "a failure that issued nothing leaves no record")
        }
    }

    func testStartIsRefusedWhileASessionOrReviewIsOpen() {
        let blocked: [ShowerState] = [authorizing(), running(), settling(),
                                      reduce(authorizing(), .authorizeFailed(.timedOut)).0]
        for s in blocked {
            XCTAssertFalse(s.canStart, "\(s.phase)")
            let (n, fx) = reduce(s, .start(machineID: machine, preferredPeripheral: nil))
            XCTAssertEqual(n, s)
            XCTAssertTrue(fx.isEmpty)
        }
    }

    // MARK: authorize

    func testAuthorizedMovesToWritePendingAndWritesPayload() {
        let (s, fx) = reduce(authorizing(), .authorized(auth, at: t0))
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertEqual(s.authorizationID, "001122FF")
        XCTAssertEqual(fx, [.scheduleReminder, .writeAuthorization(Data(count: 15))])
        XCTAssertTrue(s.mayBeFlowing)
    }

    func testUnusableAuthorizationNeedsReview() {
        let bad = [ShowerAuthorization(machineID: "99999999", payload: Data(count: 15), authorizationID: "001122FF"),
                   ShowerAuthorization(machineID: machine, payload: Data(count: 14), authorizationID: "001122FF"),
                   ShowerAuthorization(machineID: machine, payload: Data(count: 15), authorizationID: "0011")]
        for a in bad {
            let (s, fx) = reduce(authorizing(), .authorized(a, at: t0))
            XCTAssertEqual(s.failure?.reason, .authorizationInvalid)
            XCTAssertEqual(s.failure?.needsReview, true)
            XCTAssertEqual(fx, [.releaseDevice])
        }
    }

    func testDefiniteRefusalIssuesNothingButUncertaintyBlocks() {
        let refusal = ServiceError.rejected(.lxt6, code: "1", message: "余额不足")
        let (r, _) = reduce(authorizing(), .authorizeFailed(refusal))
        XCTAssertEqual(r.failure, ShowerFailure(reason: .authorizeRefused, needsReview: false, error: refusal))
        XCTAssertTrue(r.canStart)
        XCTAssertEqual(ShowerDisplay(r).title, "余额不足")

        for e in [ServiceError.timedOut, .offline, .uncertain(.lxt6), .malformed(.lxt6, "x"), .tls] {
            let (u, _) = reduce(authorizing(), .authorizeFailed(e))
            XCTAssertEqual(u.failure?.reason, .authorizeUncertain, "\(e)")
            XCTAssertEqual(u.failure?.needsReview, true)
            XCTAssertFalse(u.canStart)
            XCTAssertTrue(u.canResolveManually)
            XCTAssertFalse(u.canRetrySettle)
            XCTAssertEqual(u.persistable, u)
        }
    }

    func testCancelledBeforeAuthorizeLeftIsNotUncertain() {
        let (s, fx) = reduce(authorizing(), .cancelledBeforeSend)
        XCTAssertEqual(s.failure?.reason, .deviceUnavailable)
        XCTAssertEqual(s.failure?.needsReview, false)
        XCTAssertEqual(s.failure?.deviceError, .interrupted)
        XCTAssertEqual(fx, [.releaseDevice])
    }

    // MARK: write

    func testAckMeansRunningOtherReplyKeepsWritePendingWithNotice() {
        let (w, _) = reduce(authorizing(), .authorized(auth, at: t0))
        let (r, fx) = reduce(w, .writeReplied(FakeFrames.ack))
        XCTAssertEqual(r.phase, .running)
        XCTAssertTrue(fx.isEmpty, "link kept after authorization")

        let (p, fx2) = reduce(w, .writeReplied(Data([0xAA, 1])))
        XCTAssertEqual(p.phase, .writePending)
        XCTAssertEqual(p.notice, .writeUnconfirmed)
        XCTAssertEqual(fx2, [.releaseDevice])

        let (p2, _) = reduce(w, .writeFailed(.timedOut))
        XCTAssertEqual(p2.phase, .writePending)
        XCTAssertEqual(p2.notice, .device(.timedOut))
        let d = ShowerDisplay(p2)
        XCTAssertEqual(d.phase, .running)
        XCTAssertTrue(d.writeUnconfirmed)
        XCTAssertEqual(d.hint, ShowerDisplay.writeUnconfirmedHint)
        XCTAssertNil(p2.persistable.notice)
    }

    // MARK: finish

    func testFinishProbesThenClosesOnlyWhenActive() {
        let (c, fx) = reduce(running(), .finish)
        XCTAssertEqual(c.phase, .closing)
        XCTAssertEqual(c.closingFrom, .running)
        XCTAssertEqual(fx, [.probe(peripheralID: "P")])
        let (c2, fx2) = reduce(c, .probeReplied(FakeFrames.active))
        XCTAssertTrue(c2.closeSent)
        XCTAssertEqual(fx2, [.sendClose(Data([0xAC, 0x55, 0x44, 0x77, 0xAA]))])
        let (s, fx3) = reduce(c2, .closeReplied(consumption))
        XCTAssertEqual(s.phase, .settling)
        XCTAssertEqual(s.consumption, HexCoding.upper(consumption))
        XCTAssertEqual(fx3, [.cancelReminder, .releaseDevice, .settle(frame: consumption)])
    }

    func testFinishProbeProblemsGoBackWithoutSendingClose() {
        let (c, _) = reduce(running(), .finish)
        let cases: [(ShowerEvent, ShowerNotice)] = [
            (.probeReplied(FakeFrames.identity("99999999")), .wrongDevice),
            (.probeReplied(Data([0x01])), .device(.malformedFrame)),
            (.probeFailed(.notFound), .device(.notFound)),
            (.cancelledBeforeSend, .device(.interrupted)),
        ]
        for (event, notice) in cases {
            var from = c
            if case .cancelledBeforeSend = event { from.closeSent = true }
            let (b, fx) = reduce(from, event)
            XCTAssertEqual(b.phase, .running, "\(event)")
            XCTAssertEqual(b.notice, notice)
            XCTAssertFalse(b.closeSent)
            XCTAssertNil(b.closingFrom)
            XCTAssertEqual(fx, [.releaseDevice])
        }
        let (idle, _) = reduce(c, .probeReplied(identity))
        XCTAssertEqual(idle.phase, .running)
        XCTAssertEqual(idle.notice, .notActive)
        XCTAssertTrue(idle.stateReviewRequired)
        XCTAssertTrue(idle.canResolveManually)
    }

    func testFinishFromWritePendingWithIdleControllerEndsWithoutCharge() {
        let (w, _) = reduce(reduce(authorizing(), .authorized(auth, at: t0)).0, .writeFailed(.timedOut))
        let (c, _) = reduce(w, .finish)
        XCTAssertEqual(c.closingFrom, .writePending)
        let (i, fx) = reduce(c, .probeReplied(identity))
        XCTAssertEqual(i.phase, .idle)
        XCTAssertEqual(i.machineID, machine)
        XCTAssertTrue(fx.contains(.cancelReminder))
        XCTAssertFalse(fx.contains { if case .settle = $0 { return true }; return false })
    }

    func testFinishFromWritePendingWhenActiveCloses() {
        let (w, _) = reduce(authorizing(), .authorized(auth, at: t0))
        let (c, _) = reduce(w, .finish)
        let (c2, fx) = reduce(c, .probeReplied(FakeFrames.active))
        XCTAssertTrue(c2.closeSent)
        XCTAssertEqual(fx.count, 1)
    }

    func testCloseWithoutValidConsumptionNeedsReview() {
        let (c, _) = reduce(running(), .finish)
        let (c2, _) = reduce(c, .probeReplied(FakeFrames.active))
        for event in [ShowerEvent.closeReplied(FakeFrames.identity("99999999")), .closeReplied(FakeFrames.ack), .closeFailed(.timedOut)] {
            let (f, fx) = reduce(c2, event)
            XCTAssertEqual(f.failure?.reason, .closeUnconfirmed, "\(event)")
            XCTAssertEqual(f.failure?.needsReview, true)
            XCTAssertFalse(f.canRetrySettle)
            XCTAssertEqual(fx, [.cancelReminder, .releaseDevice])
        }
    }

    // MARK: review

    func testReviewProbeIsReadOnly() {
        let r = running()
        let (rv, fx) = reduce(r, .review)
        XCTAssertTrue(rv.reviewing)
        XCTAssertFalse(rv.canFinish)
        XCTAssertEqual(fx, [.probe(peripheralID: "P")])
        XCTAssertEqual(reduce(rv, .review).1, [], "one probe at a time")

        let (a, fxA) = reduce(rv, .probeReplied(FakeFrames.active))
        XCTAssertEqual(a.phase, .running)
        XCTAssertFalse(a.reviewing)
        XCTAssertTrue(fxA.isEmpty)

        let (i, _) = reduce(rv, .probeReplied(identity))
        XCTAssertTrue(i.stateReviewRequired)
        XCTAssertEqual(i.notice, .notActive)
        let (gone, fxR) = reduce(i, .resolveManually)
        XCTAssertEqual(gone.phase, .idle)
        XCTAssertTrue(fxR.contains(.cancelReminder))

        let (f, _) = reduce(rv, .probeFailed(.timedOut))
        XCTAssertEqual(f.notice, .device(.timedOut))
        XCTAssertEqual(f.phase, .running)
        XCTAssertFalse(reduce(r, .resolveManually).0.phase == .idle, "running without contradiction cannot be dropped")
    }

    // MARK: settle

    func testSettledIsDoneAndDismissKeepsReceipt() {
        let receipt = ShowerReceipt(amount: Money(fen: 163))
        let t1 = t0.addingTimeInterval(600)
        let (d, fx) = reduce(settling(), .settled(receipt, at: t1))
        XCTAssertEqual(d.phase, .done)
        XCTAssertEqual(d.endedAt, t1)
        XCTAssertTrue(fx.isEmpty)
        XCTAssertEqual(ShowerDisplay(d).title, "本次 ¥1.63")
        XCTAssertEqual(ShowerDisplay(ShowerState(phase: .done, receipt: ShowerReceipt(amount: nil))).title, "已结算")
        let (i, _) = reduce(d, .dismiss)
        XCTAssertEqual(i.phase, .idle)
        XCTAssertEqual(i.lastReceipt, receipt)
        let (again, _) = reduce(d, .start(machineID: machine, preferredPeripheral: nil))
        XCTAssertEqual(again.lastReceipt, receipt)
    }

    func testSettleFailureIsNeverRetriedAutomaticallyAndRetryNeedsTwoSteps() {
        for (e, reason) in [(ServiceError.timedOut, ShowerFailureReason.settleUncertain),
                            (.rejected(.lxt6, code: "7", message: "x"), .settleRefused)] {
            let (f, fx) = reduce(settling(), .settleFailed(e))
            XCTAssertEqual(f.failure?.reason, reason)
            XCTAssertTrue(fx.isEmpty, "no automatic second settle")
            XCTAssertTrue(f.canRetrySettle)
            XCTAssertFalse(f.canStart)

            XCTAssertEqual(reduce(f, .confirmSettleRetry).0, f, "confirm without request does nothing")
            let (armed, fxA) = reduce(f, .requestSettleRetry)
            XCTAssertTrue(armed.settleRetryArmed)
            XCTAssertTrue(fxA.isEmpty)
            let (s, fxS) = reduce(armed, .confirmSettleRetry)
            XCTAssertEqual(s.phase, .settling)
            XCTAssertEqual(s.manualSettleAttempts, 1)
            XCTAssertEqual(fxS, [.diagnostic("settle.manualRetry#1"), .settle(frame: consumption)])
        }
    }

    func testSettleCancelledIsUnconfirmedAndResolvable() {
        let (f, _) = reduce(settling(), .cancelledBeforeSend)
        XCTAssertEqual(f.failure?.reason, .settleUnconfirmed)
        XCTAssertEqual(ShowerDisplay(f).title, "结算待核对")
        XCTAssertEqual(ShowerDisplay(f).hint, "去看热水记录")
        XCTAssertEqual(reduce(f, .dismiss).0, f, "review failures are not dismissed")
        XCTAssertEqual(reduce(f, .resolveManually).0.phase, .idle)
    }

    // MARK: relaunch

    func testRestoreNeverResendsAndTurnsInFlightStepsIntoReview() {
        XCTAssertEqual(ShowerReducer.restore(nil), .idle)
        XCTAssertEqual(ShowerReducer.restore(running()).phase, .running)

        var notSent = authorizing()
        notSent.authorizeSent = false
        XCTAssertEqual(ShowerReducer.restore(notSent).phase, .idle)
        XCTAssertEqual(ShowerReducer.restore(authorizing()).failure?.reason, .authorizeUncertain)

        let (c, _) = reduce(running(), .finish)
        XCTAssertEqual(ShowerReducer.restore(c).phase, .running)
        let (c2, _) = reduce(c, .probeReplied(FakeFrames.active))
        XCTAssertEqual(ShowerReducer.restore(c2).failure?.reason, .closeUnconfirmed)

        let s = ShowerReducer.restore(settling())
        XCTAssertEqual(s.failure?.reason, .settleUnconfirmed)
        XCTAssertTrue(s.canRetrySettle)

        var armed = reduce(reduce(settling(), .settleFailed(.timedOut)).0, .requestSettleRetry).0
        armed.notice = .notActive
        let r = ShowerReducer.restore(armed)
        XCTAssertFalse(r.settleRetryArmed, "the two-step confirmation starts over")
        XCTAssertNil(r.notice)
    }

    func testStateRoundTripsThroughCodable() throws {
        let f = reduce(settling(), .settleFailed(.rejected(.lxt6, code: "7", message: "x"))).0
        let back = try JSONDecoder().decode(ShowerState.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
    }
}
