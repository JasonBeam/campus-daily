import Foundation

/// The full-screen shower page: one of seven faces, read from the session record. The record
/// (`ShowerState`, driven by `ShowerReducer`) stays the only truth about money; this only
/// decides what the page shows and which taps it takes.
public enum ShowerPagePhase: String, Sendable, Equatable, CaseIterable {
    /// Connecting to the controller and getting the authorization (nothing to end yet).
    case connecting
    /// Water may flow: 结束并结算 is the way out.
    case running
    /// The close went out or the settlement runs: nothing to tap.
    case settling
    /// Settled with an answer from the platform.
    case done
    /// The controller was not reached (or was not this dorm's): nothing was issued.
    case connectFailed
    /// The platform refused, or the controller is in use: nothing was issued.
    case denied
    /// The shower is over without a settlement in the app (`ShowerState.showerOver`): 结束并结算
    /// found the controller stopped, or the outcome is unknown (an authorization, close or
    /// settlement without an answer). The school settles it; the record is kept as it is, never
    /// settled again, and the page's one button is the next shower.
    case stopped
}

/// Why 结束并结算 went back to the timer (the close was not sent; water may still run).
public enum ShowerEndFailure: Sendable, Equatable {
    /// The controller was not reached.
    case noConnection
    /// The controller that answered is not this dorm's.
    case wrongController
    /// Stopped before the close went out.
    case notSent
    /// The controller runs someone else's session: no close was sent.
    case inUseByOther
    case other

    /// Nil when the notice is not an end that failed (`notActive` is the needs-check face).
    public init?(_ notice: ShowerNotice?) {
        switch notice {
        case nil, .notActive?: return nil
        case .wrongDevice?: self = .wrongController
        case .inUseByOther?: self = .inUseByOther
        case .device(.interrupted)?: self = .notSent
        case .device(.bluetoothOff)?, .device(.notFound)?, .device(.ambiguous)?, .device(.timedOut)?, .device(.disconnected)?:
            self = .noConnection
        case .device(.malformedFrame)?, .device(.busy)?, .writeUnconfirmed?: self = .other
        }
    }
}

/// What 再查一次水控 on the needs-check face found, when it stays on that face (water still
/// running goes straight back to the timer and needs no line).
public enum ShowerRecheckResult: Sendable, Equatable {
    /// The controller answered and is stopped: the check stands.
    case stopped
    /// The controller was not reached: moving closer may help.
    case noConnection
    /// The controller that answered is not this dorm's.
    case otherController
    /// Bluetooth is off.
    case bluetoothOff
    /// Something else was talking to the controller or the record (a refresh, an end): nothing
    /// was probed.
    case busy
    /// The probe ran and failed some other way (an unreadable answer, a storage error).
    case failed
    /// The probe could not start at all (the record moved on, no binding or engine yet).
    case unavailable
    /// The controller is running water that can't be this record's (it showed this session
    /// stopped before): the check stands and the link was let go.
    case inUse

    /// From the record after the probe; nil when water runs again (the timer face).
    public init?(after record: ShowerState) {
        let unconfirmedClose = record.phase == .failed && record.failure?.reason == .closeUnconfirmed
        guard record.showerOver || unconfirmedClose else { return nil }
        switch record.notice {
        case .notActive?: self = .stopped
        case .wrongDevice?: self = .otherController
        case .device(.bluetoothOff)?: self = .bluetoothOff
        case .device(.notFound)?, .device(.timedOut)?, .device(.disconnected)?, .device(.ambiguous)?, .device(.interrupted)?:
            self = .noConnection
        case .device(.busy)?: self = .busy
        case .inUseByOther?: self = .inUse
        case .device(.malformedFrame)?, .writeUnconfirmed?, nil: self = .failed
        }
    }

    /// The probe threw before it reached the controller.
    public init(error: Error) {
        switch error as? ShowerEngineError {
        case .busy?: self = .busy
        case .notAllowed?, .blocked?: self = .unavailable
        default: self = .failed
        }
    }
}

/// One of the three steps 连接 · 出水 · 结算.
public enum ShowerStepMark: String, Sendable, Equatable {
    case done, current, failed, future
}

public struct ShowerPage: Sendable, Equatable {
    /// Why the start was turned down.
    public enum Denial: Sendable, Equatable {
        /// The platform said no before it acted (a known refusal code; it gives no words then).
        case refused
        /// The controller is running for someone else.
        case inUse
    }

    public var phase: ShowerPagePhase
    /// 连接, 出水, 结算.
    public var steps: [ShowerStepMark]
    public var denial: Denial?
    /// The platform's amount; only on `done`, and only when it returned one.
    public var amount: Money?
    /// Whole minutes of water, on `done` (`ShowerState.minutes`).
    public var minutes: Int?
    /// The timer's start on `running`: when the water started (`ShowerState.startedAt`).
    public var startedAt: Date?
    /// The controller didn't confirm the authorization write; shown as running on purpose.
    public var writeUnconfirmed: Bool

    /// Nil when nothing is going on (idle): the page has nothing to show.
    public init?(_ s: ShowerState) {
        denial = nil; amount = nil; minutes = nil; startedAt = s.startedAt
        writeUnconfirmed = s.phase == .writePending
        switch s.phase {
        case .idle:
            return nil
        case .authorizing:
            phase = .connecting; steps = [.current, .future, .future]
        case .writePending where s.stateReviewRequired, .running where s.stateReviewRequired:
            // Stopped on the controller (or its authorization gone): this shower is over and the
            // school settles it. The page is back to its start layout, the bar not started.
            phase = .stopped; steps = [.future, .future, .future]
        case .writePending, .running:
            phase = .running; steps = [.done, .current, .future]
        case .closing, .settling:
            phase = .settling; steps = [.done, .done, .current]
        case .done:
            phase = .done; steps = [.done, .done, .done]
            amount = s.receipt?.amount
            minutes = s.minutes
        case .failed where s.failure?.needsReview != false:
            // Whatever the reason: a record that may have charged is kept for the school, as a
            // shower stopped on the controller is, and never shown as harmless.
            phase = .stopped; steps = [.future, .future, .future]
        case .failed:
            switch s.failure?.reason {
            case .deviceUnavailable?, .wrongDevice?:
                phase = .connectFailed; steps = [.failed, .future, .future]
            case .deviceBusy?:
                phase = .denied; steps = [.done, .failed, .future]; denial = .inUse
            case .authorizeRefused?:
                phase = .denied; steps = [.done, .failed, .future]; denial = .refused
            default:
                phase = .stopped; steps = [.future, .future, .future]
            }
        }
    }

    /// The step being worked on or the one that failed, 1-based (for 「第 2 步，共 3 步」).
    public var stepNumber: Int {
        (steps.firstIndex { $0 == .current || $0 == .failed } ?? steps.count - 1) + 1
    }
}

/// What the user did on the page, and what the record did meanwhile.
public enum ShowerPageEvent: Sendable, Equatable {
    /// 开始洗澡 on the home screen.
    case startTapped
    /// The home button in any other state (正在洗澡, 正在结算…): back to the page as it is.
    case reopen
    /// The record changed (engine update, relaunch restore).
    case record(ShowerState)
    /// 取消 while connecting.
    case cancelTapped
    /// The engine would not cancel any more (the authorize request had left).
    case cancelRefused
    /// The start request came back (whatever its outcome, or refused before anything ran).
    case startReturned
    /// 结束并结算 (also from the lock screen while the page is open).
    case endTapped
    /// The end request came back (whatever its outcome; the record says what happened).
    case endReturned
    /// The engine's end came back to the timer without sending the close, with its notice.
    case endNotSent(ShowerNotice?)
    /// 再试一次 after a connect failure.
    case retryTapped
    /// 收起 while running.
    case collapseTapped
    /// 好 (done, denied), 取消 or × (connect failed).
    case closeTapped
    /// 再查一次 (stopped, found in use): probe the controller again, read-only.
    case recheckTapped
    /// That probe came back; nil when water runs again.
    case recheckReturned(ShowerRecheckResult?)
    /// 开始下一次洗澡 (stopped).
    case startNextTapped
    /// The next start came back; `failed`: it threw before anything went out.
    case startNextReturned(failed: Bool)
    /// A copy of the page pushed on a stack (清爽) came on screen.
    case pushedAppeared
    /// A copy of the page pushed on a stack went off screen (popped, covered, its tab left).
    case pushedDisappeared
}

public enum ShowerPageEffect: Sendable, Equatable {
    case start
    /// The next shower over a stopped one (`ShowerEngine.startNext`).
    case startNext
    /// Ask the engine to stop the start (`ShowerEngine.cancelStart`).
    case cancelStart
    case finish
    /// Clear a finished or harmless record (`ShowerEngine.dismiss`).
    case dismissRecord
    /// Read-only probe of the session's controller (`ShowerEngine.review`).
    case recheck
    /// A record an older build left with 再结算一次's first tap in, and the page went away: take
    /// it back (`ShowerEngine.disarmSettleRetry`). The app offers no settle retry any more.
    case disarmSettleRetry
}

/// The page's own state: whether it is up, and the taps still waiting on the engine.
public struct ShowerPageFlow: Sendable, Equatable {
    public var record: ShowerState
    public var presented: Bool
    /// 开始洗澡 or 再试一次 was tapped and the engine has not returned yet.
    public var starting: Bool
    /// 取消 was tapped and the engine has not answered yet / the start is winding down.
    public var cancelling: Bool
    /// 结束并结算 was tapped and the engine has not returned yet.
    public var ending: Bool
    /// The last 结束并结算 came back to the timer: the line above the button says why.
    public var endFailed: ShowerEndFailure?
    /// 取消 came before the engine took up the start: it is sent once the start runs.
    public var cancelWaiting: Bool
    /// The engine refused this start's cancel: 取消 stays off until the next start.
    public var cancelRefused: Bool
    /// 再查一次水控 is probing: both bottom buttons wait for it.
    public var rechecking: Bool
    /// What the last 再查一次水控 found, shown under it while the check face stays.
    public var recheckResult: ShowerRecheckResult?
    /// Copies of the page pushed on a stack (清爽) now on screen. Such a page shows a record
    /// while the flow is down (after a relaunch).
    public private(set) var pushedShown: Int
    /// 开始下一次洗澡 was tapped and the engine has not returned yet.
    public var startingNext = false
    /// The last 开始下一次洗澡 threw before anything went out (the record could not be kept):
    /// the stopped page says it didn't go.
    public var nextFailed = false

    /// 开始下一次洗澡, the stopped page's one button (not while the controller is found in use).
    public var mayStartNext: Bool {
        page?.phase == .stopped && record.canStartNext && !foundInUse && !startingNext && !rechecking
    }

    /// The stopped page found the controller in use before the next shower (开始下一次洗澡 or
    /// 再查一次 saw water running and let it go): it says 水控有人在用, its one button 再查一次.
    /// Kept across a relaunch (`ShowerState.waitingForRelease`).
    public var foundInUse: Bool {
        page?.phase == .stopped && (record.waitingForRelease || recheckResult == .inUse)
    }

    /// While a shower is on (connecting, water, stopped on the controller, settling), every
    /// way to 热水 opens this page instead of the 热水洗澡 screen.
    /// Also over a kept failure (`ShowerState.showerOver`): it has no other screen.
    public var opensPageOnRoute: Bool {
        [ShowerPhase.authorizing, .writePending, .running, .closing, .settling].contains(record.phase) || record.showerOver
    }

    /// A pushed copy of the page is on screen.
    public var pushedVisible: Bool { pushedShown > 0 }

    /// After a relaunch the page starts closed; the home button shows where the record stands.
    public init(record: ShowerState, presented: Bool = false) {
        self.record = record; self.presented = presented; starting = false; cancelling = false; ending = false
        cancelWaiting = false; cancelRefused = false; endFailed = nil
        rechecking = false; recheckResult = nil; pushedShown = 0
    }

    /// What the page shows. A start just tapped shows 连接 at once, before the record moves
    /// off the previous shower's result.
    public var page: ShowerPage? {
        let shown = ShowerPage(record)
        if starting && record.canStart || startingNext && record.canStartNext {
            return ShowerPage(ShowerState(phase: .authorizing))
        }
        return shown
    }

    /// The running page goes down (the timer keeps going on home), and so does the stopped one:
    /// nothing there waits for an answer.
    public var mayCollapse: Bool { (page?.phase == .running || page?.phase == .stopped) && !startingNext }
    /// 再查一次 on the stopped page that found the controller in use.
    public var mayRecheck: Bool { showsRecheck && record.canReview && !rechecking }
    /// The face has 再查一次.
    public var showsRecheck: Bool { foundInUse }
    public var mayCancel: Bool { page?.phase == .connecting && !cancelling && !cancelRefused }
    public var mayEnd: Bool { page?.phase == .running && record.canFinish && !ending }
    public static func reduce(_ flow: ShowerPageFlow, _ event: ShowerPageEvent) -> (ShowerPageFlow, [ShowerPageEffect]) {
        var (next, effects) = step(flow, event)
        // Leaving the page with 再结算一次 armed (by an older build): the arm is taken back.
        // Leaving is the page going down, or the last pushed copy going off screen while it is down.
        let pushedLeft = flow.pushedVisible && !next.pushedVisible && !next.presented
        if (flow.presented && !next.presented || pushedLeft), next.record.settleRetryArmed {
            effects.append(.disarmSettleRetry)
        }
        // The first tap landed after the page went (left while it was on its way): take it back
        // too, once.
        else if !flow.presented, !next.presented, !flow.pushedVisible, !next.pushedVisible,
                next.record.settleRetryArmed, !flow.record.settleRetryArmed {
            effects.append(.disarmSettleRetry)
        }
        return (next, effects)
    }

    private static func step(_ flow: ShowerPageFlow, _ event: ShowerPageEvent) -> (ShowerPageFlow, [ShowerPageEffect]) {
        var f = flow
        switch event {
        case .startTapped:
            guard flow.record.canStart else {
                // Something is going on already: show it.
                f.presented = flow.page != nil
                return (f, [])
            }
            f.presented = true; f.starting = true; f.cancelling = false; f.ending = false
            f.cancelWaiting = false; f.cancelRefused = false; f.endFailed = nil
            // A finished record is cleared by the start itself.
            return (f, [.start])

        case .startReturned:
            f.starting = false
            if flow.cancelWaiting {
                // The start was refused before it ran: there is nothing left to cancel.
                f.cancelWaiting = false; f.cancelling = false
            }
            if f.presented, f.page == nil { f.presented = false }
            return (f, [])

        case .reopen:
            f.presented = flow.page != nil
            return (f, [])

        case .record(let next):
            f.record = next
            if flow.cancelWaiting {
                guard next.phase == .authorizing else { return (f, []) }
                f.cancelWaiting = false
                return (f, [.cancelStart])
            }
            if flow.cancelling, next.phase != .authorizing {
                f.cancelling = false
                if ShowerPage(next)?.phase == .connectFailed {
                    // The start stopped as asked: back home, no failure face, no record. A
                    // refusal that came first (the platform said no, the controller is in use)
                    // is the answer to the start and is shown.
                    f.presented = false
                    return (f, [.dismissRecord])
                }
            }
            if next.phase != .writePending, next.phase != .running, next.phase != .closing { f.ending = false }
            if !next.mayBeFlowing || next.stateReviewRequired { f.endFailed = nil }
            // Ended with the page down (from the lock screen or the Dynamic Island): the result
            // comes up, so the amount or the 不确定 face is seen.
            let wasOn = [ShowerPhase.writePending, .running, .closing, .settling].contains(flow.record.phase)
            if !flow.presented, wasOn, next.phase == .done || next.phase == .failed { f.presented = true }
            // An end from there found the controller stopped: the check comes up the same way.
            // Only an end does that; a probe from Settings leaves the page where it is.
            if !flow.presented, flow.record.phase == .closing, next.mayBeFlowing, next.stateReviewRequired { f.presented = true }
            if !f.showsRecheck, f.page?.phase != .stopped { f.recheckResult = nil }
            if f.page?.phase != .stopped { f.nextFailed = false }
            // Nothing left to show (resolved elsewhere, an authorization that never applied).
            if f.presented, !f.starting, f.page == nil { f.presented = false }
            return (f, [])

        case .cancelTapped:
            guard flow.mayCancel else { return (flow, []) }
            f.cancelling = true
            // Tapped before the engine took up the start: the engine would see no start to stop.
            guard flow.record.phase == .authorizing else { f.cancelWaiting = true; return (f, []) }
            return (f, [.cancelStart])

        case .cancelRefused:
            f.cancelling = false; f.cancelRefused = true
            return (f, [])

        case .endTapped:
            guard flow.mayEnd else { return (flow, []) }
            f.ending = true; f.endFailed = nil
            return (f, [.finish])

        case .endNotSent(let notice):
            guard flow.page?.phase == .running else { return (flow, []) }
            f.endFailed = notice == .notActive ? nil : (ShowerEndFailure(notice) ?? .other)
            return (f, [])

        case .endReturned:
            f.ending = false
            return (f, [])

        case .retryTapped:
            guard flow.page?.phase == .connectFailed, flow.record.canStart, !flow.starting else { return (flow, []) }
            f.starting = true; f.cancelRefused = false
            return (f, [.start])

        case .collapseTapped:
            guard flow.mayCollapse else { return (flow, []) }
            f.presented = false
            return (f, [])

        case .closeTapped:
            switch flow.page?.phase {
            case .done?, .denied?, .connectFailed?:
                f.presented = false
                return (f, [.dismissRecord])
            default:
                return (flow, [])
            }

        case .recheckTapped:
            guard flow.mayRecheck else { return (flow, []) }
            f.rechecking = true; f.recheckResult = nil
            return (f, [.recheck])

        case .recheckReturned(let result):
            f.rechecking = false
            f.recheckResult = f.showsRecheck ? result : nil
            // Water runs again: the timer comes up, also when the probe ran from the 热水洗澡
            // screen (the only way back to the page from there).
            if flow.rechecking, f.page?.phase == .running { f.presented = true }
            // Running, but on someone else's session: the timer says so above 结束.
            if flow.rechecking, f.page?.phase == .running, f.record.notice == .inUseByOther { f.endFailed = .inUseByOther }
            return (f, [])

        case .startNextTapped:
            guard flow.mayStartNext else { return (flow, []) }
            f.presented = true; f.startingNext = true; f.nextFailed = false; f.recheckResult = nil
            f.ending = false; f.endFailed = nil; f.cancelRefused = false
            return (f, [.startNext])

        case .startNextReturned(let failed):
            f.startingNext = false
            f.nextFailed = failed && f.page?.phase == .stopped
            if f.presented, f.page == nil { f.presented = false }
            return (f, [])

        case .pushedAppeared:
            f.pushedShown += 1
            return (f, [])

        case .pushedDisappeared:
            f.pushedShown = max(0, f.pushedShown - 1)
            return (f, [])

        }
    }
}
