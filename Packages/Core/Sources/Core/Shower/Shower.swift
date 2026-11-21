//
//  Shower.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

// Hot-water session state machine (architecture §3.1). Pure: the engine persists the state a
// transition returns *before* running its effects, so every side effect is guarded by a
// stored record of "this may have happened".

public enum ShowerPhase: String, Sendable, Codable, CaseIterable {
    case idle, authorizing, writePending, running, closing, settling, done, failed
}

/// What the BLE side can report. Codable so a failure can be stored and shown after relaunch.
public enum ShowerDeviceError: String, Error, Sendable, Codable, Equatable {
    case bluetoothOff
    /// The app may not use Bluetooth (denied or restricted in Settings), as opposed to the radio
    /// being off. A build that doesn't know it reads it as no device error (`try?`).
    case unauthorized
    case notFound
    case ambiguous
    case timedOut
    case disconnected
    case malformedFrame
    case interrupted
    case busy
}

public enum ShowerFailureReason: String, Sendable, Codable, Equatable {
    /// BLE connect/probe failed before anything was sent to the server.
    case deviceUnavailable
    /// The controller answered with another machine id (before authorize).
    case wrongDevice
    /// The controller reported itself in use (`A5`) before authorize.
    case deviceBusy
    /// The server definitely refused the authorization: nothing issued.
    case authorizeRefused
    /// Authorization outcome unknown (transport/unreadable reply): may exist server-side.
    case authorizeUncertain
    /// Server said OK but the authorization is unusable (other machine, bad payload/id).
    case authorizationInvalid
    /// Close was sent but no valid consumption frame came back.
    case closeUnconfirmed
    /// Close was sent and the controller answered that it is still busy (`A5`): no consumption,
    /// and nothing says whose water runs now. The close is never sent again for this record.
    case closeBusy
    /// Settlement explicitly refused.
    case settleRefused
    /// Settlement outcome unknown.
    case settleUncertain
    /// The app stopped while settling (relaunch) or before the request left: "结算待核对".
    case settleUnconfirmed

    /// Failed before an authorization reached the controller: no water ran, so no timer.
    public var isBeforeWater: Bool {
        switch self {
        case .deviceUnavailable, .wrongDevice, .deviceBusy, .authorizeRefused, .authorizeUncertain, .authorizationInvalid: return true
        case .closeUnconfirmed, .closeBusy, .settleRefused, .settleUncertain, .settleUnconfirmed: return false
        }
    }

    /// The close went out and its outcome is not known: water found running afterwards may be
    /// anyone's, so a check never takes the record back to the timer.
    public var isUnsureClose: Bool { self == .closeUnconfirmed || self == .closeBusy }

    /// The authorize got an answer the app can't read, or an OK whose authorization can't be
    /// used: it waits for the check, but nothing reached the controller, so no water ran and
    /// nothing is to be settled. Said as 「水没开」 (`ShowerAuthorizeUnclearText`).
    public var isUnclearAuthorize: Bool { self == .authorizeUncertain || self == .authorizationInvalid }
}

public struct ShowerFailure: Sendable, Codable, Equatable {
    public var reason: ShowerFailureReason
    /// True when something may have been issued or charged: only `resolveManually` (after the
    /// user checked the official record) clears it, and `start` stays blocked.
    public var needsReview: Bool
    public var error: ServiceError?
    public var deviceError: ShowerDeviceError?
    /// The settlement provably never left (cancelled before it, or held for the user): the
    /// school can't have charged it. False when it may have left.
    public var settleNotSent: Bool
    /// An older build held the settlement back (`ShowerState.holdSettle`), or this is a failed
    /// retry of that held frame. Kept to read such records: this build never sends it.
    public var settleHeld: Bool
    public init(reason: ShowerFailureReason, needsReview: Bool, error: ServiceError? = nil, deviceError: ShowerDeviceError? = nil,
                settleNotSent: Bool = false, settleHeld: Bool = false) {
        self.reason = reason; self.needsReview = needsReview; self.error = error; self.deviceError = deviceError
        self.settleNotSent = settleNotSent; self.settleHeld = settleHeld
    }

    /// Written by another build: without `needsReview` it is kept for a check; an error this
    /// build doesn't know is dropped (it only explains the failure).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reason = try c.decode(ShowerFailureReason.self, forKey: .reason)
        needsReview = try c.decodeIfPresent(Bool.self, forKey: .needsReview) ?? true
        error = try? c.decodeIfPresent(ServiceError.self, forKey: .error)
        deviceError = try? c.decodeIfPresent(ShowerDeviceError.self, forKey: .deviceError)
        settleNotSent = try c.decodeIfPresent(Bool.self, forKey: .settleNotSent) ?? false
        settleHeld = try c.decodeIfPresent(Bool.self, forKey: .settleHeld) ?? false
    }
}

/// A non-fatal problem during an otherwise unchanged phase (e.g. 结束 tapped but the controller
/// did not answer). Shown once; the session itself is kept.
public enum ShowerNotice: Sendable, Codable, Equatable {
    case device(ShowerDeviceError)
    /// The probe showed the controller idle with our identity while we think it runs.
    case notActive
    /// The controller answered with another machine id.
    case wrongDevice
    /// The authorization write was answered with something other than the ack.
    case writeUnconfirmed
    /// Water found running where it can't be this record's: after a close that went out, or
    /// on a controller the record already showed stopped. Nothing more was sent.
    case inUseByOther
    /// A check found water running on a controller our authorization provably never reached:
    /// the record stays as it is, and 结束 closes and settles that water as any other.
    case waterRunning
}

public struct ShowerState: Sendable, Codable, Equatable {
    public var phase: ShowerPhase
    public var machineID: String?
    /// The controller this session talks to; finish/review never use another one.
    public var peripheralID: String?
    /// When water may start flowing (出水: the authorization arrived and is being written), not
    /// the 开始洗澡 tap: connecting and authorizing are not shower time. The one origin of the
    /// in-app timer, the Live Activity, the 「还没结束洗澡？」 reminder and the shown duration.
    /// Never used for billing (the controller's consumption frame is). Nil before the water.
    /// Records saved before this rule hold the tap time here (see `ShowerReducer.restore`).
    public var startedAt: Date?
    /// Persisted right before the authorize request leaves.
    public var authorizeSent: Bool
    public var authorizationID: String?
    /// The phase `finish` came from (to go back if the close is not sent).
    public var closingFrom: ShowerPhase?
    /// Persisted right before the close command is written.
    public var closeSent: Bool
    /// Upper-hex consumption frame to settle.
    public var consumption: String?
    public var receipt: ShowerReceipt?
    public var lastReceipt: ShowerReceipt?
    public var failure: ShowerFailure?
    /// The device contradicted the record (probe idle while "running"): kept for review.
    public var stateReviewRequired: Bool
    /// A review probe is in flight (phase unchanged).
    public var reviewing: Bool
    /// First tap of a manual settle retry; the second confirmation sends it.
    public var settleRetryArmed: Bool
    /// Manual settle retries made on this record (whether the school dedupes a settlement is not
    /// known). Kept in the record only; nothing shows or exports it.
    public var manualSettleAttempts: Int
    public var endedAt: Date?
    public var notice: ShowerNotice?
    /// The authorization write provably never reached the controller (cancelled before it, or
    /// the write was refused): no water could run, so an idle controller at 结束 ends the
    /// record without a check. An unconfirmed write may have been applied and never sets it.
    public var authorizationNotWritten: Bool
    /// Saved by older builds: the next consumption frame was to be held, not settled. Never set
    /// by this one, and cleared on restore (`ShowerReducer.restore`): an end settles the close's
    /// own reply as any other. Kept so such records still decode.
    public var holdSettle: Bool
    /// When the session came back to the timer from the unsure face (a probe found water
    /// running after an unconfirmed close). The 「还在计时」 reminder counts from here, also after
    /// a relaunch: the water start may be long past.
    public var timerResumedAt: Date?
    /// The consumption frame an older build held (`holdSettle`), upper hex. Never sent by this
    /// build (`canRetrySettle`).
    public var heldConsumption: String?
    /// The next use over this record found the controller still in use (`A5`): the link was
    /// let go and nothing was authorized. The record waits for the user to try again or check it.
    /// Kept across a relaunch; a record that lost its authorization never sends a close.
    public var waitingForRelease: Bool
    /// After a close whose outcome is unknown (`ShowerFailureReason.isUnsureClose`), a read-only
    /// check found this controller idle. The record stays as it is (failed, its fee to be checked
    /// on the campus card); only the automatic check stops and the page says the shower is over.
    public var closeStopSeen: Bool
    /// The hot-water student the session was opened with (`ShowerBinding.studentId`). 结束 with a
    /// binding of another student is refused before anything is sent. Nil on records saved
    /// before it was kept: never filled in afterwards. Stays in the Keychain record only.
    public var studentId: String?

    public init(phase: ShowerPhase = .idle, machineID: String? = nil, peripheralID: String? = nil, startedAt: Date? = nil,
                authorizeSent: Bool = false, authorizationID: String? = nil, closingFrom: ShowerPhase? = nil,
                closeSent: Bool = false, consumption: String? = nil, receipt: ShowerReceipt? = nil,
                lastReceipt: ShowerReceipt? = nil, failure: ShowerFailure? = nil, stateReviewRequired: Bool = false,
                reviewing: Bool = false, settleRetryArmed: Bool = false, manualSettleAttempts: Int = 0,
                endedAt: Date? = nil, notice: ShowerNotice? = nil, authorizationNotWritten: Bool = false,
                holdSettle: Bool = false, timerResumedAt: Date? = nil, heldConsumption: String? = nil,
                waitingForRelease: Bool = false, closeStopSeen: Bool = false, studentId: String? = nil) {
        self.phase = phase; self.machineID = machineID; self.peripheralID = peripheralID; self.startedAt = startedAt
        self.authorizeSent = authorizeSent; self.authorizationID = authorizationID; self.closingFrom = closingFrom
        self.closeSent = closeSent; self.consumption = consumption; self.receipt = receipt; self.lastReceipt = lastReceipt
        self.failure = failure; self.stateReviewRequired = stateReviewRequired; self.reviewing = reviewing
        self.settleRetryArmed = settleRetryArmed; self.manualSettleAttempts = manualSettleAttempts
        self.endedAt = endedAt; self.notice = notice; self.authorizationNotWritten = authorizationNotWritten
        self.holdSettle = holdSettle; self.timerResumedAt = timerResumedAt; self.heldConsumption = heldConsumption
        self.waitingForRelease = waitingForRelease
        self.closeStopSeen = closeStopSeen; self.studentId = studentId
    }

    public static let idle = ShowerState()

    /// `start` is allowed only from idle, done, or a failure that issued nothing.
    public var canStart: Bool {
        switch phase {
        case .idle, .done: return true
        case .failed: return failure?.needsReview == false
        default: return false
        }
    }

    /// Not once the controller showed this session stopped (`stateReviewRequired`): water found
    /// running after that may be anyone's, and a close would settle it under this record.
    public var canFinish: Bool {
        (phase == .writePending || phase == .running) && !reviewing && !stateReviewRequired && !waitingForRelease
    }

    /// A read-only probe of the controller: while water may run (also while that waits for the
    /// check), and from a close that may not have taken (it only reports what it finds: the
    /// close is never sent again).
    /// Also over a kept failure the next start found in use (`waitingForRelease`): 再查一次.
    public var canReview: Bool {
        ((phase == .writePending || phase == .running) && !reviewing)
            || (phase == .failed && failure?.reason.isUnsureClose == true && !reviewing)
            || (phase == .failed && failure?.needsReview == true && waitingForRelease && !reviewing)
    }

    /// The next use (`ShowerEngine.startNext`) over a record that waits for the user's check:
    /// the record is kept as it is (`ShowerVault.retainShower`), never settled, and the next use
    /// verifies the controller again and gets a new authorization.
    public var canStartNext: Bool { canResolveManually }

    public var canResolveManually: Bool {
        (phase == .failed && failure?.needsReview == true)
            || ((phase == .writePending || phase == .running) && stateReviewRequired && !reviewing)
    }

    /// The frame to settle is the one that was held.
    public var consumptionHeld: Bool { consumption != nil && consumption == heldConsumption }

    /// Never for end data an older build held back (`settleHeld`, or the frame alone saying so):
    /// it is not sent by this build.
    public var canRetrySettle: Bool {
        phase == .failed && failure?.needsReview == true && consumption != nil
            && failure?.settleHeld != true && !consumptionHeld
            && [ShowerFailureReason.settleRefused, .settleUncertain, .settleUnconfirmed].contains { $0 == failure?.reason }
    }

    /// The shower is over without a settlement in the app, and the school settles it: stopped
    /// on the controller, or a failure whose outcome is unknown (`needsReview`). Such a record is
    /// kept as it is, never settled again; the next step is the next shower (`canStartNext`).
    public var showerOver: Bool {
        (mayBeFlowing && stateReviewRequired) || (phase == .failed && failure?.needsReview == true)
    }

    /// The reminder ("还没结束洗澡？") runs while water may be flowing.
    public var mayBeFlowing: Bool { phase == .writePending || phase == .running }

    /// What the 「还在计时」 reminder counts from: the return to the timer, else the water start.
    /// Nil when no water may be flowing.
    public var reminderStart: Date? { mayBeFlowing ? (timerResumedAt ?? startedAt) : nil }

    /// Whole minutes of water on `done` (「上次 11 分钟」, the done page, the settled lock screen).
    public var minutes: Int? { phase == .done ? endedAt.flatMap(minutes(until:)) : nil }

    /// Whole minutes from the water start to `end`, at least 1.
    public func minutes(until end: Date) -> Int? {
        guard let start = startedAt else { return nil }
        return max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    /// What goes to the Keychain. A failure that issued nothing leaves no record.
    public var persistable: ShowerState {
        var s = self
        s.notice = nil
        s.reviewing = false
        if phase == .failed, failure?.needsReview == false {
            return idleAfter(receipt: lastReceipt)
        }
        return s
    }

    fileprivate func idleAfter(receipt: ShowerReceipt?) -> ShowerState {
        ShowerState(phase: .idle, machineID: machineID, peripheralID: peripheralID, lastReceipt: receipt)
    }
}

extension ShowerState {
    /// A record saved by another build (older or newer). The phase is required: without
    /// it the record means nothing, and guessing one could hide an open shower. So are the
    /// machine and the controller of a shower that may still be open: 结束 and the checks go to
    /// that controller only, and without it they would take the only one in range and could
    /// close a shower that is not ours. A missing "sent" flag counts as sent (the request may
    /// have left); other missing flags get their defaults. Unknown values in fields that only
    /// describe the record are dropped.
    public init(from decoder: Decoder) throws { try self.init(from: decoder, live: true) }

    /// `live: false` reads a row kept in `water.retained`: it is only shown, never ended,
    /// checked or settled, so an open shower there may lack its controller. Every other rule
    /// is the live record's.
    init(from decoder: Decoder, live: Bool) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decode(ShowerPhase.self, forKey: .phase)
        machineID = try c.decodeIfPresent(String.self, forKey: .machineID)
        peripheralID = try c.decodeIfPresent(String.self, forKey: .peripheralID)
        if live, [.writePending, .running, .closing].contains(phase), machineID == nil || peripheralID == nil {
            throw DecodingError.dataCorruptedError(forKey: .peripheralID, in: c, debugDescription: "an open shower names its controller")
        }
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        authorizeSent = try c.decodeIfPresent(Bool.self, forKey: .authorizeSent) ?? true
        authorizationID = try c.decodeIfPresent(String.self, forKey: .authorizationID)
        closingFrom = try? c.decodeIfPresent(ShowerPhase.self, forKey: .closingFrom)
        closeSent = try c.decodeIfPresent(Bool.self, forKey: .closeSent) ?? true
        consumption = try c.decodeIfPresent(String.self, forKey: .consumption)
        receipt = try c.decodeIfPresent(ShowerReceipt.self, forKey: .receipt)
        lastReceipt = try? c.decodeIfPresent(ShowerReceipt.self, forKey: .lastReceipt)
        failure = try c.decodeIfPresent(ShowerFailure.self, forKey: .failure)
        if phase == .failed, failure == nil {
            // A failure is what offers the check; without one the record would have no way out.
            failure = ShowerFailure(reason: .settleUnconfirmed, needsReview: true)
        }
        stateReviewRequired = try c.decodeIfPresent(Bool.self, forKey: .stateReviewRequired) ?? false
        reviewing = try c.decodeIfPresent(Bool.self, forKey: .reviewing) ?? false
        settleRetryArmed = try c.decodeIfPresent(Bool.self, forKey: .settleRetryArmed) ?? false
        manualSettleAttempts = try c.decodeIfPresent(Int.self, forKey: .manualSettleAttempts) ?? 0
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        notice = try? c.decodeIfPresent(ShowerNotice.self, forKey: .notice)
        authorizationNotWritten = try c.decodeIfPresent(Bool.self, forKey: .authorizationNotWritten) ?? false
        holdSettle = try c.decodeIfPresent(Bool.self, forKey: .holdSettle) ?? false
        timerResumedAt = try? c.decodeIfPresent(Date.self, forKey: .timerResumedAt)
        heldConsumption = try? c.decodeIfPresent(String.self, forKey: .heldConsumption)
        waitingForRelease = try c.decodeIfPresent(Bool.self, forKey: .waitingForRelease) ?? false
        closeStopSeen = try c.decodeIfPresent(Bool.self, forKey: .closeStopSeen) ?? false
        studentId = try? c.decodeIfPresent(String.self, forKey: .studentId)
    }
}

public enum ShowerEvent: Sendable, Equatable {
    /// `studentId`: the hot-water binding's student, kept with the new record.
    case start(machineID: String, preferredPeripheral: String?, studentId: String? = nil)
    /// Connected and probed (`AA`) before authorize.
    case connected(peripheralID: String, probe: Data)
    case connectFailed(ShowerDeviceError)
    /// `at`: when the authorization arrived, i.e. when water may start (the timer's origin).
    case authorized(ShowerAuthorization, at: Date)
    case authorizeFailed(ServiceError)
    case writeReplied(Data)
    case writeFailed(ShowerDeviceError)
    case finish
    case review
    case probeReplied(Data)
    case probeFailed(ShowerDeviceError)
    case closeReplied(Data)
    case closeFailed(ShowerDeviceError)
    case settled(ShowerReceipt, at: Date)
    case settleFailed(ServiceError)
    /// The task was cancelled after the state was persisted but before the request/write left.
    case cancelledBeforeSend
    case requestSettleRetry
    case confirmSettleRetry
    /// The page with the armed retry was left: the next tap only arms it again.
    case disarmSettleRetry
    case resolveManually
    case dismiss
}

public enum ShowerEffect: Sendable, Equatable {
    /// Connect to the controller (preferring `preferred`), then write `AA` → `.connected`/`.connectFailed`.
    case connectAndProbe(machineID: String, preferred: String?)
    /// POST authorize with the identity frame → `.authorized`/`.authorizeFailed`.
    case authorize(frame: Data)
    /// Write the 15-byte authorization → `.writeReplied`/`.writeFailed`.
    case writeAuthorization(Data)
    /// Connect to exactly `peripheralID` and write `AA` → `.probeReplied`/`.probeFailed`.
    case probe(peripheralID: String?)
    /// Write the close command → `.closeReplied`/`.closeFailed`.
    case sendClose(Data)
    /// POST settle with the consumption frame → `.settled`/`.settleFailed`. Never emitted automatically twice.
    case settle(frame: Data)
    case releaseDevice
    /// Drop `peripheralID` from the saved binding: it answered with another machine's identity.
    case forgetPeripheral(String)
    /// A note for the hooks (`ShowerHooks.diagnostic`).
    case diagnostic(ShowerDiagnostic)
}

public enum ShowerReducer {
    /// Errors that are a definite "no" from the service (nothing was issued/charged).
    public static func isDefiniteRefusal(_ e: ServiceError) -> Bool {
        switch e {
        case .rejected, .badRequest, .sessionExpired, .officialUnfinishedOrder: return true
        default: return false
        }
    }

    /// An authorize answer that proves nothing was issued: a refusal before anything was sent,
    /// or one of the codes the platform is known to answer before it acts on a request
    /// (`LxtClient.requestRefusalCodes`, both `badRequest`). Any other non-zero code is
    /// `rejected` and may come after the authorization was created, so it is not one.
    public static func isDefiniteAuthorizeRefusal(_ e: ServiceError) -> Bool {
        switch e {
        case .badRequest, .sessionExpired: return true
        default: return false
        }
    }

    public static func reduce(_ state: ShowerState, _ event: ShowerEvent) -> (ShowerState, [ShowerEffect]) {
        var s = state
        s.notice = nil
        switch (state.phase, event) {

        // MARK: start
        case (_, .start(let machine, let preferred, let student)) where state.canStart:
            // Keep the controller remembered for this machine, so a failed connect does not
            // forget it and the next start can still try it before scanning.
            let remembered = preferred ?? (state.machineID == machine.uppercased() ? state.peripheralID : nil)
            let n = ShowerState(phase: .authorizing, machineID: machine.uppercased(), peripheralID: remembered,
                                lastReceipt: state.phase == .done ? state.receipt : state.lastReceipt, studentId: student)
            return (n, [.connectAndProbe(machineID: machine.uppercased(), preferred: preferred)])

        case (.authorizing, .connected(let peripheral, let probe)) where !state.authorizeSent:
            // Only a controller that answered with this machine's identity is remembered.
            switch ShowerFrames.classify(probe) {
            case .idle(let id) where id == state.machineID:
                s.peripheralID = peripheral
                s.authorizeSent = true
                return (s, [.authorize(frame: probe)])
            case .idle where state.peripheralID != nil && peripheral == state.peripheralID:
                // The remembered controller answered as another machine (it was never this one,
                // or the dorm's controller was replaced): forget it and scan once without it.
                s.peripheralID = nil
                return (s, [.forgetPeripheral(peripheral), .releaseDevice,
                            .connectAndProbe(machineID: state.machineID ?? "", preferred: nil)])
            case .idle:
                return (failed(s, .wrongDevice, review: false), [.releaseDevice])
            case .active:
                return (failed(s, .deviceBusy, review: false), [.releaseDevice])
            case .unreadable:
                return (failed(s, .deviceUnavailable, review: false, device: .malformedFrame), [.releaseDevice])
            }

        case (.authorizing, .connectFailed(let e)) where !state.authorizeSent:
            return (failed(s, .deviceUnavailable, review: false, device: e), [.releaseDevice])

        case (.authorizing, .cancelledBeforeSend) where state.authorizeSent:
            // Persisted "sent" but the request never left: nothing issued.
            s.authorizeSent = false
            return (failed(s, .deviceUnavailable, review: false, device: .interrupted), [.releaseDevice])

        case (.authorizing, .authorized(let auth, let at)) where state.authorizeSent:
            guard auth.machineID.uppercased() == state.machineID,
                  auth.payload.count == ShowerFrames.authorizationLength,
                  ShowerFrames.closeCommand(authorizationID: auth.authorizationID) != nil else {
                return (failed(s, .authorizationInvalid, review: true), [.releaseDevice])
            }
            s.phase = .writePending
            s.authorizationID = auth.authorizationID.uppercased()
            // 出水: the timer, the Live Activity and the reminder (scheduled here) start now.
            s.startedAt = at
            return (s, [.writeAuthorization(auth.payload)])

        case (.authorizing, .authorizeFailed(let e)) where state.authorizeSent:
            if isDefiniteAuthorizeRefusal(e) {
                return (failed(s, .authorizeRefused, review: false, error: e), [.releaseDevice])
            }
            // A code we don't know (or 4060, an unfinished order at the school) keeps its answer
            // with the record; nothing else is assumed from it.
            if case .rejected = e {
                return (failed(s, .authorizeUncertain, review: true, error: e), [.releaseDevice])
            }
            if e == .officialUnfinishedOrder {
                return (failed(s, .authorizeUncertain, review: true, error: e), [.releaseDevice])
            }
            return (failed(s, .authorizeUncertain, review: true, error: .uncertain(.lxt6)), [.releaseDevice])

        // MARK: authorization write
        case (.writePending, .writeReplied(let frame)) where !state.reviewing:
            if ShowerFrames.isAck(frame) {
                s.phase = .running
                // The official client keeps the link after authorization.
                return (s, [])
            }
            s.notice = .writeUnconfirmed
            return (s, [.releaseDevice])

        case (.writePending, .writeFailed(let e)):
            s.notice = .device(e)
            return (s, [.releaseDevice])

        case (.writePending, .cancelledBeforeSend) where !state.reviewing:
            // The authorization never reached the controller.
            s.authorizationNotWritten = true
            s.notice = .device(.interrupted)
            return (s, [.releaseDevice])

        // MARK: finish / review
        case (.writePending, .finish), (.running, .finish):
            guard state.canFinish else { return (state, []) }
            s.phase = .closing
            s.closingFrom = state.phase
            s.closeSent = false
            return (s, [.probe(peripheralID: state.peripheralID)])

        case (.writePending, .review), (.running, .review):
            guard !state.reviewing else { return (state, []) }
            s.reviewing = true
            return (s, [.probe(peripheralID: state.peripheralID)])

        case (.writePending, .probeReplied(let frame)), (.running, .probeReplied(let frame)):
            guard state.reviewing else { return (state, []) }
            s.reviewing = false
            switch ShowerFrames.classify(frame) {
            case .active where state.stateReviewRequired || state.waitingForRelease:
                // The controller already showed this session stopped: that shower is over, and
                // water running now is someone else's (or a new one). It never resumes the old
                // session; the link is let go.
                s.notice = .inUseByOther
                return (s, [.releaseDevice])
            case .active where state.authorizationNotWritten:
                // Our authorization provably never reached it: the record stays waiting on its
                // write (not the confirmed timer) and says water runs; 结束 closes and settles it.
                s.notice = .waterRunning
                return (s, [.releaseDevice])
            case .active:
                s.phase = .running
                s.stateReviewRequired = false
                return (s, [])
            case .idle(let id) where id == state.machineID && state.phase == .writePending && state.authorizationNotWritten:
                // The authorization never reached the controller and nothing runs: no water, no
                // charge. The record ends as 结束 ends it (which checks `from == .writePending`).
                return (state.idleAfter(receipt: state.lastReceipt),
                        [.releaseDevice, .diagnostic(.reviewWriteNeverApplied)])
            case .idle(let id) where id == state.machineID:
                // Stopped, and free again for the next shower.
                s.stateReviewRequired = true
                s.waitingForRelease = false
                s.notice = .notActive
            case .idle:
                s.notice = .wrongDevice
            case .unreadable:
                s.notice = .device(.malformedFrame)
            }
            return (s, [.releaseDevice])

        case (.writePending, .probeFailed(let e)), (.running, .probeFailed(let e)):
            guard state.reviewing else { return (state, []) }
            s.reviewing = false
            s.notice = .device(e)
            return (s, [.releaseDevice])

        case (.failed, .review) where state.canReview:
            s.reviewing = true
            return (s, [.probe(peripheralID: state.peripheralID)])

        case (.failed, .probeReplied(let frame)) where state.reviewing
                && (state.failure?.reason.isUnsureClose == true || state.waitingForRelease):
            s.reviewing = false
            switch ShowerFrames.classify(frame) {
            case .active:
                // Water running after a close that went out (or after the next use let the link
                // go): nothing says whose it is, and a second close could stop someone else's
                // water. The record stays as it is, never back on the timer; the link is let go.
                s.notice = .inUseByOther
            case .idle(let id) where id == state.machineID:
                // Stopped: the close may have taken, or water stopped by itself. The record stays
                // as it is (its fee to be checked), and is free again for the next shower. After
                // an unsure close this is saved: the automatic check stops for good, and a later
                // A5 changes none of it.
                s.waitingForRelease = false
                if state.failure?.reason.isUnsureClose == true { s.closeStopSeen = true }
                s.notice = .notActive
            case .idle:
                s.notice = .wrongDevice
            case .unreadable:
                s.notice = .device(.malformedFrame)
            }
            return (s, [.releaseDevice])

        case (.failed, .probeFailed(let e)) where state.reviewing:
            s.reviewing = false
            s.notice = .device(e)
            return (s, [.releaseDevice])

        case (.closing, .probeReplied(let frame)) where !state.closeSent:
            let from = state.closingFrom ?? .running
            switch ShowerFrames.classify(frame) {
            case .active:
                // Also over an authorization that provably never reached the controller: the
                // owner's choice is to close that water and settle the close's reply.
                guard let id = state.authorizationID, let command = ShowerFrames.closeCommand(authorizationID: id) else {
                    return (back(s, to: from, notice: .writeUnconfirmed), [.releaseDevice])
                }
                s.closeSent = true
                s.stateReviewRequired = false
                return (s, [.sendClose(command)])
            case .idle(let id) where id == state.machineID:
                if from == .writePending, state.authorizationNotWritten {
                    // The authorization never reached the controller: no water, no charge.
                    return (state.idleAfter(receipt: state.lastReceipt), [.releaseDevice, .diagnostic(.finishWriteNeverApplied)])
                }
                // Stopped now, but an unconfirmed write may have been applied and run water.
                var b = back(s, to: from, notice: .notActive)
                b.stateReviewRequired = true
                return (b, [.releaseDevice])
            case .idle:
                return (back(s, to: from, notice: .wrongDevice), [.releaseDevice])
            case .unreadable:
                return (back(s, to: from, notice: .device(.malformedFrame)), [.releaseDevice])
            }

        case (.closing, .probeFailed(let e)) where !state.closeSent:
            return (back(s, to: state.closingFrom ?? .running, notice: .device(e)), [.releaseDevice])

        case (.closing, .cancelledBeforeSend) where state.closeSent:
            s.closeSent = false
            return (back(s, to: state.closingFrom ?? .running, notice: .device(.interrupted)), [.releaseDevice])

        case (.closing, .closeReplied(let frame)) where state.closeSent:
            if ShowerFrames.classify(frame) == .active {
                // Still busy: the close went out, no consumption came back. Kept for the check.
                return (failed(s, .closeBusy, review: true, device: .busy), [.releaseDevice])
            }
            guard ShowerFrames.identity(frame) == state.machineID else {
                return (failed(s, .closeUnconfirmed, review: true, device: .malformedFrame), [.releaseDevice])
            }
            // Only this close's own reply, from this machine, as it came: settled once.
            s.consumption = HexCoding.upper(frame)
            s.holdSettle = false
            s.phase = .settling
            return (s, [.releaseDevice, .settle(frame: frame)])

        case (.closing, .closeFailed(let e)) where state.closeSent:
            return (failed(s, .closeUnconfirmed, review: true, device: e), [.releaseDevice])

        // MARK: settle
        case (.settling, .settled(let receipt, let at)):
            s.phase = .done
            s.receipt = receipt
            s.lastReceipt = receipt
            s.endedAt = at
            s.failure = nil
            return (s, [])

        case (.settling, .settleFailed(let e)):
            let reason: ShowerFailureReason = isDefiniteRefusal(e) ? .settleRefused : .settleUncertain
            return (failed(s, reason, review: true, error: e, settleHeld: state.consumptionHeld), [])

        case (.settling, .cancelledBeforeSend):
            return (failed(s, .settleUnconfirmed, review: true, settleNotSent: true, settleHeld: state.consumptionHeld), [])

        case (.failed, .requestSettleRetry) where state.canRetrySettle:
            s.settleRetryArmed = true
            return (s, [])

        case (.failed, .confirmSettleRetry) where state.canRetrySettle && state.settleRetryArmed:
            guard let hex = state.consumption, let frame = HexCoding.data(hex) else { return (state, []) }
            s.phase = .settling
            s.settleRetryArmed = false
            s.manualSettleAttempts += 1
            s.failure = nil
            return (s, [.diagnostic(.settleManualRetry(s.manualSettleAttempts)), .settle(frame: frame)])

        case (.failed, .disarmSettleRetry) where state.settleRetryArmed:
            s.settleRetryArmed = false
            return (s, [])

        // MARK: leaving
        case (_, .resolveManually) where state.canResolveManually:
            return (state.idleAfter(receipt: state.lastReceipt), [.releaseDevice, .diagnostic(.resolvedManually(state.phase))])

        case (.done, .dismiss):
            return (state.idleAfter(receipt: state.receipt), [])

        case (.failed, .dismiss) where state.failure?.needsReview == false:
            return (state.idleAfter(receipt: state.lastReceipt), [])

        default:
            return (state, [])
        }
    }

    /// Relaunch: what a persisted record means now. Nothing is re-sent automatically.
    public static func restore(_ persisted: ShowerState?) -> ShowerState {
        guard var s = persisted else { return .idle }
        // Records saved before the timer counted from the water hold the tap time in
        // `startedAt`. A record that never reached the water drops it (no timer); one past it
        // keeps it, so a running timer and its reminder don't jump back after the update.
        if s.phase == .authorizing || (s.phase == .failed && s.failure?.reason.isBeforeWater == true) {
            s.startedAt = nil
        }
        s.notice = nil
        s.reviewing = false
        s.settleRetryArmed = false
        // An older build's hold on the next end data: this build settles a close's reply as any
        // other. A frame it already held stays held (`canRetrySettle`).
        s.holdSettle = false
        switch s.phase {
        case .idle, .done, .writePending, .running:
            return s
        case .failed:
            return s.failure?.needsReview == false ? s.idleAfter(receipt: s.lastReceipt) : s
        case .authorizing:
            // Not sent: nothing issued. Sent: the authorization may exist.
            return s.authorizeSent ? failed(s, .authorizeUncertain, review: true, error: .uncertain(.lxt6))
                                   : s.idleAfter(receipt: s.lastReceipt)
        case .closing:
            if s.closeSent { return failed(s, .closeUnconfirmed, review: true, device: .interrupted) }
            return back(s, to: s.closingFrom ?? .running, notice: nil)
        case .settling:
            return failed(s, .settleUnconfirmed, review: true, settleHeld: s.consumptionHeld)
        }
    }

    private static func failed(_ s: ShowerState, _ reason: ShowerFailureReason, review: Bool,
                               error: ServiceError? = nil, device: ShowerDeviceError? = nil,
                               settleNotSent: Bool = false, settleHeld: Bool = false) -> ShowerState {
        var f = s
        f.phase = .failed
        f.reviewing = false
        f.settleRetryArmed = false
        f.failure = ShowerFailure(reason: reason, needsReview: review, error: error, deviceError: device,
                                  settleNotSent: settleNotSent, settleHeld: settleHeld)
        return f
    }

    private static func back(_ s: ShowerState, to phase: ShowerPhase, notice: ShowerNotice?) -> ShowerState {
        var b = s
        b.phase = phase
        b.closingFrom = nil
        b.closeSent = false
        b.notice = notice
        return b
    }
}

// MARK: - Presentation

/// The record's words where a caller speaks or shows a line instead of the page (Siri,
/// Shortcuts, the lock screen, the status line).
public enum ShowerDisplay {
    /// Under the timer while the controller did not confirm the authorization write (shown as
    /// running on purpose): the page, home, the lock screen and the island.
    public static let writeUnconfirmedHint = "水控没回应，有热水就照常洗"

    /// One line for the record.
    public static func title(_ s: ShowerState) -> String {
        switch s.phase {
        case .idle: return "开水"
        case .authorizing: return "正在开水…"
        case .writePending, .running: return s.stateReviewRequired ? ShowerAuthorText.keptStatus : "洗澡中"
        case .closing: return "正在结束…"
        case .settling: return "正在结算…"
        case .done: return s.receipt?.amount.map { "本次 ¥\($0.yuanText)" } ?? "已结算"
        case .failed:
            // A check saw the controller stopped after the unsure close: the kept words.
            if s.closeStopSeen, s.failure?.reason.isUnsureClose == true { return ShowerAuthorText.keptStatus }
            return failureTitle(s.failure)
        }
    }

    public static func failureTitle(_ f: ShowerFailure?) -> String {
        guard let f else { return "出了点问题" }
        switch f.reason {
        case .deviceUnavailable: return "没连上水控，靠近一点再试。"
        case .wrongDevice: return "这不是你宿舍的水控。"
        case .deviceBusy: return "水控正在使用中。"
        case .authorizeRefused: return ShowerAuthorizeRefusedText.title
        case .authorizeUncertain, .authorizationInvalid: return ShowerAuthorizeUnclearText.title(platformMessage: f.platformMessage)
        // Over without an answer: the school settles it (`ShowerState.showerOver`).
        case .closeBusy: return ShowerAuthorText.closeBusyStatus
        case .closeUnconfirmed, .settleRefused, .settleUncertain, .settleUnconfirmed: return ShowerAuthorText.keptStatus
        }
    }
}

public extension ShowerFailure {
    /// The platform's own sentence, when it answered with one (`rejected`), or the words for
    /// its unfinished-order refusal (4060).
    var platformMessage: String? {
        if error == .officialUnfinishedOrder { return ServiceError.unfinishedOrderMessage }
        guard case .rejected(_, _, let message)? = error else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
