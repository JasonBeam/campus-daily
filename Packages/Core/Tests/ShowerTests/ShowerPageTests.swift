import XCTest
@testable import Core

final class ShowerPageTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func failed(_ reason: ShowerFailureReason, review: Bool, error: ServiceError? = nil) -> ShowerState {
        ShowerState(phase: .failed, machineID: "11223344", startedAt: t0,
                    failure: ShowerFailure(reason: reason, needsReview: review, error: error))
    }

    func reduce(_ flow: inout ShowerPageFlow, _ event: ShowerPageEvent) -> [ShowerPageEffect] {
        let (next, effects) = ShowerPageFlow.reduce(flow, event)
        flow = next
        return effects
    }

    // MARK: Faces

    func testEachRecordShowsItsFace() {
        XCTAssertNil(ShowerPage(.idle))
        let cases: [(ShowerState, ShowerPagePhase, [ShowerStepMark])] = [
            (ShowerState(phase: .authorizing), .connecting, [.current, .future, .future]),
            (ShowerState(phase: .writePending, startedAt: t0), .running, [.done, .current, .future]),
            (ShowerState(phase: .running, startedAt: t0), .running, [.done, .current, .future]),
            (ShowerState(phase: .closing, startedAt: t0), .settling, [.done, .done, .current]),
            (ShowerState(phase: .settling, startedAt: t0), .settling, [.done, .done, .current]),
            (ShowerState(phase: .done, startedAt: t0), .done, [.done, .done, .done]),
            (failed(.deviceUnavailable, review: false), .connectFailed, [.failed, .future, .future]),
            (failed(.wrongDevice, review: false), .connectFailed, [.failed, .future, .future]),
            (failed(.deviceBusy, review: false), .denied, [.done, .failed, .future]),
            (failed(.authorizeRefused, review: false), .denied, [.done, .failed, .future]),
            (failed(.authorizeUncertain, review: true), .unsure, [.done, .failed, .future]),
            (failed(.authorizationInvalid, review: true), .unsure, [.done, .failed, .future]),
            (failed(.closeUnconfirmed, review: true), .unsure, [.done, .done, .failed]),
            (failed(.settleRefused, review: true), .unsure, [.done, .done, .failed]),
            (failed(.settleUncertain, review: true), .unsure, [.done, .done, .failed]),
            (failed(.settleUnconfirmed, review: true), .unsure, [.done, .done, .failed]),
        ]
        for (state, phase, steps) in cases {
            let page = ShowerPage(state)
            XCTAssertEqual(page?.phase, phase, "\(state.phase) \(String(describing: state.failure?.reason))")
            XCTAssertEqual(page?.steps, steps, "\(state.phase) \(String(describing: state.failure?.reason))")
        }
        XCTAssertTrue(ShowerPage(ShowerState(phase: .writePending))!.writeUnconfirmed)
        XCTAssertEqual(ShowerPage(ShowerState(phase: .running))?.stepNumber, 2)
        XCTAssertEqual(ShowerPage(failed(.deviceUnavailable, review: false))?.stepNumber, 1)
    }

    /// A failure that may have charged is never shown as harmless, whatever its reason.
    func testARecordThatMayHaveChargedIsAlwaysUnsure() {
        for reason in [ShowerFailureReason.deviceUnavailable, .wrongDevice, .deviceBusy, .authorizeRefused] {
            XCTAssertEqual(ShowerPage(failed(reason, review: true))?.phase, .unsure, reason.rawValue)
            XCTAssertNil(ShowerPage(failed(reason, review: true))?.denial)
        }
    }

    func testDenialSaysWhy() {
        XCTAssertEqual(ShowerPage(failed(.deviceBusy, review: false))?.denial, .inUse)
        XCTAssertEqual(ShowerPage(failed(.authorizeRefused, review: false, error: .rejected(.lxt6, code: "1", message: "余额不足")))?.denial,
                       .refused("余额不足"))
        XCTAssertEqual(ShowerPage(failed(.authorizeRefused, review: false, error: .badRequest(.lxt6)))?.denial, .refused(nil))
    }

    /// Only the platform's amount is shown, and minutes only with both ends known.
    func testDoneShowsOnlyThePlatformsAmount() {
        var s = ShowerState(phase: .done, startedAt: t0, receipt: ShowerReceipt(amount: Money(fen: 132)), endedAt: t0.addingTimeInterval(11 * 60 + 10))
        XCTAssertEqual(ShowerPage(s)?.amount, Money(fen: 132))
        XCTAssertEqual(ShowerPage(s)?.minutes, 11)
        s.receipt = ShowerReceipt(amount: nil)
        XCTAssertNil(ShowerPage(s)?.amount)
        s.receipt = nil; s.endedAt = nil
        XCTAssertNil(ShowerPage(s)?.amount)
        XCTAssertNil(ShowerPage(s)?.minutes)
        XCTAssertEqual(ShowerPage(ShowerState(phase: .done, startedAt: t0, endedAt: t0.addingTimeInterval(5)))?.minutes, 1)
    }

    // MARK: Flow

    func testAWholeShower() {
        var flow = ShowerPageFlow(record: .idle)
        XCTAssertEqual(reduce(&flow, .startTapped), [.start])
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(flow.page?.phase, .connecting, "connecting at once")
        _ = reduce(&flow, .record(ShowerState(phase: .authorizing, startedAt: t0)))
        _ = reduce(&flow, .record(ShowerState(phase: .running, startedAt: t0)))
        _ = reduce(&flow, .startReturned)
        XCTAssertEqual(flow.page?.phase, .running)
        XCTAssertTrue(flow.mayCollapse)
        XCTAssertEqual(reduce(&flow, .endTapped), [.finish])
        _ = reduce(&flow, .record(ShowerState(phase: .closing, startedAt: t0)))
        XCTAssertFalse(flow.mayCollapse, "settling can't be left")
        _ = reduce(&flow, .record(ShowerState(phase: .settling, startedAt: t0)))
        _ = reduce(&flow, .record(ShowerState(phase: .done, startedAt: t0, receipt: ShowerReceipt(amount: Money(fen: 132)))))
        _ = reduce(&flow, .endReturned)
        XCTAssertEqual(flow.page?.phase, .done)
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(reduce(&flow, .closeTapped), [.dismissRecord])
        XCTAssertFalse(flow.presented)
    }

    /// A second 结束 (double tap, or the lock screen as well) while the first runs does nothing.
    func testDuplicateEndTapsFinishOnce() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0), presented: true)
        XCTAssertEqual(reduce(&flow, .endTapped), [.finish])
        XCTAssertEqual(reduce(&flow, .endTapped), [])
        _ = reduce(&flow, .record(ShowerState(phase: .closing, startedAt: t0)))
        XCTAssertEqual(reduce(&flow, .endTapped), [])
        // The close was not sent (controller didn't answer): back to running, 结束 works again.
        _ = reduce(&flow, .record(ShowerState(phase: .running, startedAt: t0)))
        _ = reduce(&flow, .endReturned)
        XCTAssertEqual(reduce(&flow, .endTapped), [.finish])
    }

    func testCancelWhileConnectingGoesHomeWithNoRecord() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .startTapped)
        _ = reduce(&flow, .record(ShowerState(phase: .authorizing, startedAt: t0)))
        XCTAssertEqual(reduce(&flow, .cancelTapped), [.cancelStart])
        XCTAssertEqual(reduce(&flow, .cancelTapped), [], "once")
        let effects = reduce(&flow, .record(failed(.deviceUnavailable, review: false)))
        XCTAssertEqual(effects, [.dismissRecord])
        XCTAssertFalse(flow.presented, "no failure face for a cancel")
        _ = reduce(&flow, .startReturned)
        XCTAssertFalse(flow.presented)
    }

    /// 取消 right after 开始洗澡, before the engine took up the start: it waits for the start
    /// to run and is sent then, instead of being refused.
    func testACancelBeforeTheStartRunsIsSentOnceItRuns() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .done, startedAt: t0))
        _ = reduce(&flow, .startTapped)
        XCTAssertTrue(flow.mayCancel)
        XCTAssertEqual(reduce(&flow, .cancelTapped), [])
        XCTAssertFalse(flow.mayCancel)
        XCTAssertEqual(reduce(&flow, .record(.idle)), [])
        XCTAssertEqual(reduce(&flow, .record(ShowerState(phase: .authorizing, startedAt: t0))), [.cancelStart])
        let effects = reduce(&flow, .record(failed(.deviceUnavailable, review: false)))
        XCTAssertEqual(effects, [.dismissRecord])
        XCTAssertFalse(flow.presented)

        // The start was refused before it ran: the waiting cancel is dropped.
        var refused = ShowerPageFlow(record: .idle)
        _ = reduce(&refused, .startTapped)
        _ = reduce(&refused, .cancelTapped)
        _ = reduce(&refused, .startReturned)
        XCTAssertFalse(refused.cancelling)
        XCTAssertFalse(refused.cancelWaiting)
    }

    /// The authorize request had left: the cancel is refused and the page follows the start.
    func testARefusedCancelFollowsTheStart() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .authorizing, startedAt: t0), presented: true)
        _ = reduce(&flow, .cancelTapped)
        _ = reduce(&flow, .cancelRefused)
        XCTAssertFalse(flow.mayCancel, "取消 can't be tapped again for nothing")
        _ = reduce(&flow, .record(ShowerState(phase: .running, startedAt: t0)))
        XCTAssertEqual(flow.page?.phase, .running)
        XCTAssertTrue(flow.presented)
    }

    /// 取消 as the controller or the platform turns the start down: the refusal is shown (nothing
    /// was charged), the page does not just close.
    func testACancelMeetingARefusalShowsTheRefusal() {
        for (reason, denial) in [(ShowerFailureReason.authorizeRefused, ShowerPage.Denial.refused(nil)), (.deviceBusy, .inUse)] {
            var flow = ShowerPageFlow(record: ShowerState(phase: .authorizing, startedAt: t0), presented: true)
            XCTAssertEqual(reduce(&flow, .cancelTapped), [.cancelStart])
            XCTAssertEqual(reduce(&flow, .record(failed(reason, review: false))), [], "\(reason)")
            XCTAssertTrue(flow.presented)
            XCTAssertEqual(flow.page?.phase, .denied)
            XCTAssertEqual(flow.page?.denial, denial)
            XCTAssertEqual(reduce(&flow, .closeTapped), [.dismissRecord])
        }
    }

    /// A cancel that arrives as the start runs into an uncertain authorization: that is shown.
    func testACancelNeverHidesAnUncertainRecord() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .authorizing, startedAt: t0), presented: true)
        _ = reduce(&flow, .cancelTapped)
        let effects = reduce(&flow, .record(failed(.authorizeUncertain, review: true)))
        XCTAssertEqual(effects, [])
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(flow.page?.phase, .unsure)
    }

    // MARK: Needs check

    /// The record says water runs but the controller showed itself stopped: the needs-check
    /// face, not the timer. No end, no start; 去核对 and 核对过了 only.
    func testAStoppedControllerShowsTheNeedsCheckFace() {
        for phase in [ShowerPhase.running, .writePending] {
            let page = ShowerPage(ShowerState(phase: phase, startedAt: t0, stateReviewRequired: true))
            XCTAssertEqual(page?.phase, .needsCheck, "\(phase)")
            XCTAssertEqual(page?.steps, [.done, .done, .failed])
        }
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, machineID: "11223344", startedAt: t0), presented: true)
        XCTAssertEqual(reduce(&flow, .endTapped), [.finish])
        _ = reduce(&flow, .record(ShowerState(phase: .closing, machineID: "11223344", startedAt: t0, closingFrom: .running)))
        let back = ShowerState(phase: .running, machineID: "11223344", startedAt: t0, stateReviewRequired: true, notice: .notActive)
        _ = reduce(&flow, .record(back))
        _ = reduce(&flow, .endNotSent(.notActive))
        _ = reduce(&flow, .endReturned)
        XCTAssertEqual(flow.page?.phase, .needsCheck)
        XCTAssertNil(flow.endFailed, "the face says it, not an end-failed line")
        XCTAssertTrue(flow.presented)
        XCTAssertFalse(flow.mayEnd)
        XCTAssertTrue(flow.mayResolve)
        XCTAssertFalse(flow.mayCollapse, "no 收起 and no swipe: the check is answered on the page")
        for event in [ShowerPageEvent.endTapped, .startTapped, .retryTapped, .cancelTapped, .closeTapped, .collapseTapped] {
            XCTAssertEqual(ShowerPageFlow.reduce(flow, event).1, [], "\(event)")
        }
        var review = flow
        XCTAssertEqual(reduce(&review, .reviewTapped), [.openReview])
        XCTAssertFalse(review.presented)
        XCTAssertEqual(reduce(&flow, .resolveTapped), [.resolveManually])
        _ = reduce(&flow, .record(.idle))
        XCTAssertFalse(flow.presented, "checked: nothing left to show")

        // A review probe in flight: 核对过了 waits for it.
        var probing = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, reviewing: true),
                                     presented: true)
        XCTAssertFalse(probing.mayResolve)
        XCTAssertEqual(reduce(&probing, .resolveTapped), [])
        XCTAssertEqual(ShowerHomeStatus.needsCheck.asksForSchoolSignIn(signedIn: false), false)
    }

    /// Ended from the lock screen with the page down, and the controller was stopped: the
    /// check comes up.
    func testANeedsCheckFromTheLockScreenComesUp() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0))
        _ = reduce(&flow, .record(ShowerState(phase: .closing, startedAt: t0, closingFrom: .running)))
        _ = reduce(&flow, .record(ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive)))
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(flow.page?.phase, .needsCheck)
    }

    /// 再查一次水控 on the check face: both buttons wait; still running goes back to the timer
    /// with no line; stopped or not reached stays with a line under it.
    func testRecheckingTheControllerFromTheCheckFace() {
        let check = ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive)
        var flow = ShowerPageFlow(record: check, presented: true)
        XCTAssertTrue(flow.mayRecheck)
        XCTAssertEqual(reduce(&flow, .recheckTapped), [.recheck])
        XCTAssertTrue(flow.rechecking)
        XCTAssertFalse(flow.mayResolve)
        XCTAssertEqual(reduce(&flow, .reviewTapped), [], "去核对 waits for the probe")
        XCTAssertEqual(reduce(&flow, .recheckTapped), [], "one probe at a time")

        var stopped = flow
        _ = reduce(&stopped, .record(check))
        _ = reduce(&stopped, .recheckReturned(ShowerRecheckResult(after: check)))
        XCTAssertEqual(stopped.recheckResult, .stopped)
        XCTAssertTrue(stopped.mayResolve)

        var away = flow
        let notReached = ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .device(.notFound))
        _ = reduce(&away, .record(notReached))
        _ = reduce(&away, .recheckReturned(ShowerRecheckResult(after: notReached)))
        XCTAssertEqual(away.recheckResult, .noConnection)
        XCTAssertTrue(away.mayRecheck, "can be tried again")

        let flowing = ShowerState(phase: .running, startedAt: t0)
        XCTAssertNil(ShowerRecheckResult(after: flowing))
        _ = reduce(&flow, .record(flowing))
        _ = reduce(&flow, .recheckReturned(nil))
        XCTAssertEqual(flow.page?.phase, .running, "straight back to the timer")
        XCTAssertNil(flow.recheckResult)
        XCTAssertTrue(flow.mayEnd)
        XCTAssertTrue(flow.presented)
    }

    /// 再查一次水控 on the 热水洗澡 screen (the page down): water running again brings the
    /// timer up; a stopped controller leaves the page down.
    func testARecheckFromTheShowerScreenBringsTheTimerUpOnlyWhenWaterRuns() {
        let check = ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive)
        var stopped = ShowerPageFlow(record: check)
        XCTAssertEqual(reduce(&stopped, .recheckTapped), [.recheck])
        _ = reduce(&stopped, .record(check))
        _ = reduce(&stopped, .recheckReturned(.stopped))
        XCTAssertFalse(stopped.presented)
        XCTAssertEqual(stopped.recheckResult, .stopped)

        var flowing = ShowerPageFlow(record: check)
        _ = reduce(&flowing, .recheckTapped)
        _ = reduce(&flowing, .record(ShowerState(phase: .running, startedAt: t0)))
        XCTAssertFalse(flowing.presented, "the record alone does not bring it up")
        _ = reduce(&flowing, .recheckReturned(nil))
        XCTAssertTrue(flowing.presented)
        XCTAssertEqual(flowing.page?.phase, .running)

        var idle = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0))
        _ = reduce(&idle, .recheckReturned(nil))
        XCTAssertFalse(idle.presented, "only an answer to a probe that was running")
    }

    /// What 再查一次水控 says: Bluetooth off, something else busy, an unreadable answer and a
    /// probe that could not start each get their own line, not 「没连上」.
    func testRecheckResultsTellTheFailuresApart() {
        func after(_ notice: ShowerNotice?) -> ShowerRecheckResult? {
            ShowerRecheckResult(after: ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: notice))
        }
        XCTAssertEqual(after(.device(.bluetoothOff)), .bluetoothOff)
        XCTAssertEqual(after(.device(.notFound)), .noConnection)
        XCTAssertEqual(after(.device(.timedOut)), .noConnection)
        XCTAssertEqual(after(.device(.busy)), .busy)
        XCTAssertEqual(after(.device(.malformedFrame)), .failed)
        XCTAssertEqual(after(.wrongDevice), .otherController)
        XCTAssertEqual(ShowerRecheckResult(error: ShowerEngineError.busy), .busy)
        XCTAssertEqual(ShowerRecheckResult(error: ShowerEngineError.notAllowed), .unavailable)
        XCTAssertEqual(ShowerRecheckResult(error: ShowerEngineError.storage), .failed)
        XCTAssertEqual(ShowerRecheckResult(error: ShowerEngineError.wrongBinding), .failed)

        let check = ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive)
        var flow = ShowerPageFlow(record: check, presented: true)
        _ = reduce(&flow, .recheckTapped)
        _ = reduce(&flow, .recheckReturned(.unavailable))
        XCTAssertEqual(flow.recheckResult, .unavailable, "a probe that could not start still says so")
        XCTAssertFalse(flow.rechecking)
    }

    /// 检查水控状态 in Settings found the controller stopped: the record waits for a check, but
    /// Settings stays open (only an end brings the check up by itself).
    func testAProbeFromSettingsDoesNotBringTheCheckUp() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0))
        _ = reduce(&flow, .record(ShowerState(phase: .running, startedAt: t0, reviewing: true)))
        _ = reduce(&flow, .record(ShowerState(phase: .running, startedAt: t0, stateReviewRequired: true, notice: .notActive)))
        XCTAssertFalse(flow.presented)
        XCTAssertEqual(flow.page?.phase, .needsCheck, "the home button still says 核对上次洗澡")
    }

    /// 结束并结算 came back to the timer: a line says why, until the next tap.
    func testAnEndThatWasNotSentSaysWhy() {
        let cases: [(ShowerNotice?, ShowerEndFailure)] = [
            (.device(.notFound), .noConnection), (.device(.timedOut), .noConnection), (.device(.bluetoothOff), .noConnection),
            (.device(.disconnected), .noConnection), (.wrongDevice, .wrongController), (.device(.interrupted), .notSent),
            (.device(.malformedFrame), .other), (.writeUnconfirmed, .other), (nil, .other),
        ]
        for (notice, expected) in cases {
            var flow = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0), presented: true)
            _ = reduce(&flow, .endTapped)
            _ = reduce(&flow, .record(ShowerState(phase: .running, startedAt: t0, notice: notice)))
            _ = reduce(&flow, .endNotSent(notice))
            _ = reduce(&flow, .endReturned)
            XCTAssertEqual(flow.endFailed, expected, "\(String(describing: notice))")
            XCTAssertEqual(flow.page?.phase, .running)
            XCTAssertTrue(flow.mayEnd)
            _ = reduce(&flow, .endTapped)
            XCTAssertNil(flow.endFailed, "gone on the next tap")
        }
        // Settled after all: no line.
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0), presented: true)
        _ = reduce(&flow, .endNotSent(.device(.notFound)))
        _ = reduce(&flow, .record(ShowerState(phase: .settling, startedAt: t0)))
        XCTAssertNil(flow.endFailed)
    }

    /// The settlement timed out: 不确定, with no way to settle again from the page.
    func testASettlementTimeoutIsUnsureWithoutRetry() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .settling, startedAt: t0), presented: true)
        _ = reduce(&flow, .record(failed(.settleUncertain, review: true, error: .timedOut)))
        XCTAssertEqual(flow.page?.phase, .unsure)
        for event in [ShowerPageEvent.endTapped, .retryTapped, .startTapped, .closeTapped, .cancelTapped] {
            XCTAssertEqual(ShowerPageFlow.reduce(flow, event).1, [], "\(event)")
        }
        var toReview = flow
        XCTAssertEqual(reduce(&toReview, .reviewTapped), [.openReview])
        XCTAssertFalse(toReview.presented)
        var toHome = flow
        XCTAssertEqual(reduce(&toHome, .homeTapped), [], "the record stays for 核对")
        XCTAssertFalse(toHome.presented)
    }

    func testRetryAfterAConnectFailure() {
        var flow = ShowerPageFlow(record: failed(.deviceUnavailable, review: false), presented: true)
        XCTAssertEqual(reduce(&flow, .retryTapped), [.start])
        XCTAssertEqual(flow.page?.phase, .connecting)
        XCTAssertEqual(reduce(&flow, .retryTapped), [], "not twice")
        var closing = ShowerPageFlow(record: failed(.deviceUnavailable, review: false), presented: true)
        XCTAssertEqual(reduce(&closing, .closeTapped), [.dismissRecord])
        XCTAssertFalse(closing.presented)
    }

    func testCollapseOnlyWhileRunningAndReopenAsItIs() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0), presented: true)
        _ = reduce(&flow, .collapseTapped)
        XCTAssertFalse(flow.presented)
        _ = reduce(&flow, .reopen)
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(flow.page?.phase, .running)
        for state in [ShowerState(phase: .authorizing), ShowerState(phase: .settling), failed(.settleUncertain, review: true)] {
            var other = ShowerPageFlow(record: state, presented: true)
            _ = reduce(&other, .collapseTapped)
            XCTAssertTrue(other.presented, "\(state.phase)")
        }
    }

    /// Relaunched in the middle: the page starts closed and opens on the restored record.
    func testRelaunchMidShower() {
        let running = ShowerReducer.restore(ShowerState(phase: .running, machineID: "11223344", startedAt: t0))
        var flow = ShowerPageFlow(record: running)
        XCTAssertFalse(flow.presented)
        _ = reduce(&flow, .reopen)
        XCTAssertEqual(flow.page?.phase, .running)
        XCTAssertTrue(flow.mayEnd)

        let settling = ShowerReducer.restore(ShowerState(phase: .settling, machineID: "11223344", startedAt: t0, closeSent: true))
        XCTAssertEqual(ShowerPageFlow(record: settling).page?.phase, .unsure, "killed while settling")

        let sent = ShowerReducer.restore(ShowerState(phase: .authorizing, machineID: "11223344", startedAt: t0, authorizeSent: true))
        XCTAssertEqual(ShowerPageFlow(record: sent).page?.phase, .unsure)
        let notSent = ShowerReducer.restore(ShowerState(phase: .authorizing, machineID: "11223344", startedAt: t0))
        var idle = ShowerPageFlow(record: notSent)
        XCTAssertNil(idle.page)
        _ = reduce(&idle, .reopen)
        XCTAssertFalse(idle.presented, "nothing to show")
    }

    /// 开始洗澡 with a record still open shows that record and starts nothing.
    func testStartWithAnOpenRecordShowsIt() {
        var flow = ShowerPageFlow(record: failed(.closeUnconfirmed, review: true))
        XCTAssertEqual(reduce(&flow, .startTapped), [])
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(flow.page?.phase, .unsure)
    }

    /// A start refused before it ran (a reset in progress): the page closes again.
    func testAStartThatNeverRanClosesThePage() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .startTapped)
        _ = reduce(&flow, .startReturned)
        XCTAssertFalse(flow.presented)
    }

    /// The record went back to idle (the authorization never applied, or resolved elsewhere).
    func testARecordThatEndsQuietlyClosesThePage() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0), presented: true)
        _ = reduce(&flow, .endTapped)
        _ = reduce(&flow, .record(.idle))
        XCTAssertFalse(flow.presented)
        XCTAssertFalse(flow.ending)
    }

    /// Ended from the lock screen with the page down: the result comes up.
    func testAShowerEndedElsewhereShowsItsResult() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, startedAt: t0))
        _ = reduce(&flow, .record(ShowerState(phase: .settling, startedAt: t0)))
        XCTAssertFalse(flow.presented)
        _ = reduce(&flow, .record(ShowerState(phase: .done, startedAt: t0, receipt: ShowerReceipt(amount: Money(fen: 132)))))
        XCTAssertTrue(flow.presented)
        var unsure = ShowerPageFlow(record: ShowerState(phase: .settling, startedAt: t0))
        _ = reduce(&unsure, .record(failed(.settleUncertain, review: true)))
        XCTAssertTrue(unsure.presented)
        var quiet = ShowerPageFlow(record: .idle)
        _ = reduce(&quiet, .record(ShowerState(phase: .done, startedAt: t0)))
        XCTAssertFalse(quiet.presented, "a restored result does not jump up")
    }
}
