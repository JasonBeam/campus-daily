import Foundation

/// One line of the TestFlight debug log (`DebugLogSink`). Every field is a fixed enum, a number,
/// a flag or a salted tag (`DebugTag`): no case takes free text, a frame, a request or a reply,
/// so a password, a token or a server's sentence has nowhere to go.
public enum DebugEvent: Sendable, Equatable {
    // MARK: Hot water (`ShowerEngine`)
    case showerAction(DebugShowerAction)
    case showerPhase(from: ShowerPhase, to: DebugShowerState)
    /// The saved record at launch and what it means now; `unreadable`: the read failed.
    case showerRestore(saved: ShowerPhase?, restored: ShowerPhase, unreadable: Bool)
    case showerNote(ShowerDiagnostic)
    case bleConnect(DebugConnect)
    case bleProbe(DebugFrame, DebugProbeVerdict)
    /// The authorization write (always 15 bytes out) and what came back.
    case bleAuthWrite(DebugWrite)
    /// The close command, once `closeSent` is saved, and what came back.
    case bleClose(DebugWrite)
    case lxtAuthorize(DebugAuthorizeStep)
    case lxtSettle(DebugSettleStep)

    // MARK: Laundry (`LaundryEngine`)
    case laundryPhase(from: LaundryPhase, to: LaundryPhase, outcome: DebugCode?)
    case laundryRequest(DebugLaundryRequest, DebugOutcome)
    /// U净's order status code, the machine's module type when the read had it, the order's tag.
    case laundryOrder(status: DebugCode, moduleType: Int?, order: DebugTag?)
    case laundryPayLaunch(opened: Bool)
    /// 立刻洗衣: the choice, the return, the pre-start read, the start and why it was not sent.
    case laundryStart(DebugLaundryStart)

    // MARK: School and U净 logins
    case schoolRefresh(DebugSchoolOutcome)
    case schoolCredentialExpired(kind: DebugCredential, ageMinutes: Int?, aliveMinutes: Int?)
    case schoolSavedLogin(DebugPasswordStep)
    /// The portal token traded for a new card session.
    case schoolRenew(DebugSchoolOutcome)
    case ujingLogin(DebugOutcome)

    // MARK: Network and pages
    case http(DebugHTTP)
    case navOpen(DebugPage, from: DebugEntry)
}

/// What the user did on the hot-water record.
public enum DebugShowerAction: Sendable, Equatable {
    case start(machine: DebugTag)
    /// 开始下一次洗澡 over a shower that is over.
    case startNext(machine: DebugTag)
    /// 开始洗澡 from Siri or Shortcuts: `next`, over a shower that is over, it is 开始下一次洗澡.
    case shortcutStart(next: Bool)
    case finish, review, dismiss
    case cancelStart(accepted: Bool)
}

/// The engine's own notes (were plain strings): `name` keeps the old event names.
public enum ShowerDiagnostic: Sendable, Equatable {
    /// 开始下一次洗澡's probe: in use (nothing sent), another controller, a frame nobody can read,
    /// or cancelled while it connected or probed.
    case nextUseDeviceBusy, nextUseWrongDevice, nextUseUnreadable, nextUseCancelled
    /// The stopped record saved aside and read back: only then is the new one authorized.
    case nextUseRecordKept
    /// It could not be saved or read back: nothing was authorized.
    case nextUseKeepFailed
    /// The new record could not be saved: nothing went out, the stopped one stands.
    case nextUseNotSaved
    case reviewWriteNeverApplied, finishWriteNeverApplied
    case settleHeldAfterUnconfirmedClose
    case settleManualRetry(Int)
    case resolvedManually(ShowerPhase)

    public var name: String {
        switch self {
        case .nextUseDeviceBusy: return "nextUse.deviceBusy"
        case .nextUseWrongDevice: return "nextUse.wrongDevice"
        case .nextUseUnreadable: return "nextUse.unreadable"
        case .nextUseCancelled: return "nextUse.cancelled"
        case .nextUseRecordKept: return "nextUse.recordKept.readBackOK"
        case .nextUseKeepFailed: return "nextUse.keepFailed"
        case .nextUseNotSaved: return "nextUse.newRecordNotSaved"
        case .reviewWriteNeverApplied: return "review.writeNeverApplied"
        case .finishWriteNeverApplied: return "finish.writeNeverApplied"
        case .settleHeldAfterUnconfirmedClose: return "settle.heldAfterUnconfirmedClose"
        case .settleManualRetry(let n): return "settle.manualRetry#\(n)"
        case .resolvedManually(let phase): return "resolvedManually.\(phase.rawValue)"
        }
    }
}

/// The parts of a hot-water record that say where it stands: phase, failure and flags. No ids,
/// frames or times.
public struct DebugShowerState: Sendable, Equatable {
    public enum Notice: String, Sendable { case device, notActive, wrongDevice, writeUnconfirmed, inUseByOther }
    public var phase: ShowerPhase
    public var failure: ShowerFailureReason?
    public var deviceError: ShowerDeviceError?
    public var errorKind: DebugErrorKind?
    public var needsReview: Bool
    public var settleNotSent: Bool
    public var settleHeld: Bool
    public var holdSettle: Bool
    public var stateReviewRequired: Bool
    public var waitingForRelease: Bool
    public var authorizationNotWritten: Bool
    public var reviewing: Bool
    /// Over without a settlement in the app: the school settles it (`ShowerState.showerOver`).
    public var showerOver: Bool
    public var notice: Notice?
    public var noticeDevice: ShowerDeviceError?

    public init(_ s: ShowerState) {
        phase = s.phase
        failure = s.failure?.reason
        deviceError = s.failure?.deviceError
        errorKind = s.failure?.error.map(DebugErrorKind.init)
        needsReview = s.failure?.needsReview ?? false
        settleNotSent = s.failure?.settleNotSent ?? false
        settleHeld = s.failure?.settleHeld ?? false
        holdSettle = s.holdSettle
        stateReviewRequired = s.stateReviewRequired
        waitingForRelease = s.waitingForRelease
        authorizationNotWritten = s.authorizationNotWritten
        reviewing = s.reviewing
        showerOver = s.showerOver
        switch s.notice {
        case .device(let e)?: notice = .device; noticeDevice = e
        case .notActive?: notice = .notActive
        case .wrongDevice?: notice = .wrongDevice
        case .writeUnconfirmed?: notice = .writeUnconfirmed
        case .inUseByOther?: notice = .inUseByOther
        case nil: notice = nil
        }
    }
}

/// A connect to the controller.
public struct DebugConnect: Sendable, Equatable {
    public enum Target: String, Sendable { case required, preferred, scanned }
    /// Nil: connected.
    public var error: ShowerDeviceError?
    public var target: Target
    /// The peripheral reached is the one the record already had (nil: none known or no connect).
    public var samePeripheral: Bool?
    public init(error: ShowerDeviceError?, target: Target, samePeripheral: Bool?) {
        self.error = error; self.target = target; self.samePeripheral = samePeripheral
    }
}

/// A controller frame as its first byte and length only: never the machine id or the 15 bytes after it.
public struct DebugFrame: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case lead55 = "55", leadAA = "AA", leadA5 = "A5", other, empty
    }
    public var kind: Kind
    public var length: Int
    public init(_ frame: Data) {
        length = frame.count
        switch frame.first {
        case 0x55?: kind = .lead55
        case 0xAA?: kind = .leadAA
        case 0xA5?: kind = .leadA5
        case nil: kind = .empty
        default: kind = .other
        }
    }
}

public enum DebugProbeVerdict: String, Sendable {
    case idleSelf, idleOther, active, unreadable

    public init(_ frame: Data, machineID: String?) {
        switch ShowerFrames.classify(frame) {
        case .active: self = .active
        case .idle(let id): self = id == machineID?.uppercased() ? .idleSelf : .idleOther
        case .unreadable: self = .unreadable
        }
    }
}

/// A write to the controller and its answer.
public enum DebugWrite: Sendable, Equatable {
    /// Never reached the controller (`ShowerCommandNotSent`, or cancelled before it).
    case notSent
    case failed(ShowerDeviceError)
    /// `matches`: for the authorization the ack (9 bytes, `AA`); for the close a 20-byte `55`
    /// consumption frame with this machine's id.
    case replied(DebugFrame, matches: Bool)
}

public enum DebugAuthorizeStep: Sendable, Equatable {
    case sent
    /// The authorization's data length and whether its id is 8 hex characters (never the id).
    case ok(dataLength: Int, idIsHex8: Bool)
    case failed(DebugError)
    case notSent
}

public enum DebugSettleStep: Sendable, Equatable {
    /// The one settlement after the close.
    case sent
    case ok(fen: Int?)
    case failed(DebugError)
    case notSent
}

public enum DebugLaundryRequest: String, Sendable {
    case create, orderDetail, paymentMethods, paymentArguments, cancelOrder, findActive
    /// 立刻洗衣's pre-start read and `control/start`.
    case startCheck, startWasher
}

/// One step of 立刻洗衣 (`LaundryEngine`). No order id (only its tag), no machine, no reply text.
public enum DebugLaundryStart: Sendable, Equatable {
    /// The order was confirmed as 立刻洗衣 (`yes`) or 正常洗衣 (`no`).
    case chosen(immediate: Bool)
    /// Back from Alipay, or a refresh, on a 立刻洗衣 order not tried yet: whether the app was in front.
    case returned(inFront: Bool)
    /// The pre-start read: paid, U净's status code, the price against the confirmed one, the module type.
    case check(paid: Bool, status: DebugCode, price: DebugPriceCheck, moduleType: Int?, order: DebugTag?)
    /// The start was stored as sent (before the request).
    case saved
    /// `control/start` was handed to the network.
    case handed
    case result(DebugStartResult)
    /// Not sent (this time, or for good).
    case skipped(DebugStartSkip)
}

/// The pre-start read's price, in fen, against the confirmed program's.
public enum DebugPriceCheck: String, Sendable {
    case ok, mismatch, unreadable

    public init(read: Money?, confirmed: Money?) {
        guard let read = read?.fen, let confirmed = confirmed?.fen, read > 0 else { self = .unreadable; return }
        self = read <= confirmed ? .ok : .mismatch
    }
}

/// `control/start`'s answer: taken, refused (U净's code only, never its words) or not clear.
public enum DebugStartResult: Sendable, Equatable {
    case ok
    case refused(DebugCode?)
    case unknown(DebugErrorKind)

    public init(_ error: ServiceError?) {
        switch error {
        case nil: self = .ok
        case .rejected(_, let code, _)?: self = .refused(DebugCode(code))
        case let e?: self = .unknown(DebugErrorKind(e))
        }
    }
}

/// Why `control/start` was not sent.
public enum DebugStartSkip: String, Sendable {
    /// The app was not in front, or the task was cancelled before the request.
    case notFront, cancelled
    /// More than 10 minutes after the order was confirmed.
    case expired
    /// The signed-in U净 account did not place the order.
    case account
    /// The machine is left to the U净 app (`LaundryStartBlock`).
    case unsupported, offline, selfClean, dispenser
    /// The pre-start read was another order, not paid 20, or at a price that did not match.
    case otherOrder, status, price
    /// The "sent" record could not be stored.
    case notSaved

    public init(_ block: LaundryStartBlock) {
        switch block {
        case .unsupported: self = .unsupported
        case .offline: self = .offline
        case .selfClean: self = .selfClean
        case .dispenser: self = .dispenser
        case .expired: self = .expired
        case .account: self = .account
        case .price: self = .price
        }
    }
}

public enum DebugSchoolOutcome: Sendable, Equatable {
    case ok, notSignedIn, needsLogin(DebugError), leaseLost, interrupted, failed(DebugError)

    public init(_ outcome: SchoolReading.Outcome) {
        switch outcome {
        case .ok: self = .ok
        case .notSignedIn: self = .notSignedIn
        case .needsLogin(let e): self = .needsLogin(DebugError(e))
        case .leaseLost: self = .leaseLost
        case .interrupted: self = .interrupted
        case .failed(let e): self = .failed(DebugError(e))
        }
    }
}

public enum DebugCredential: String, Sendable { case card, portal }

public enum DebugPasswordStep: Sendable, Equatable {
    public enum Reason: String, Sendable { case noLoginDeviceID, credentialsChanged, deviceIDNotSaved }
    case sent
    case deferred(Reason)
    case skipped(Reason)
}

public enum DebugOutcome: Sendable, Equatable {
    case ok
    case failed(DebugError)

    public init(_ error: Error?) {
        guard let error else { self = .ok; return }
        self = .failed(DebugError(error))
    }
}

public enum DebugErrorKind: String, Sendable {
    case offline, timedOut, tls, sessionExpired, rejected, badRequest, malformed, uncertain, other

    public init(_ e: ServiceError) {
        switch e {
        case .offline: self = .offline
        case .timedOut: self = .timedOut
        case .tls: self = .tls
        case .sessionExpired: self = .sessionExpired
        case .rejected, .officialUnfinishedOrder: self = .rejected
        case .badRequest: self = .badRequest
        case .malformed: self = .malformed
        case .uncertain: self = .uncertain
        }
    }
}

/// A `ServiceError` as its kind, service and (`rejected`) code. The server's sentence and the
/// `malformed` field path are dropped.
public struct DebugError: Sendable, Equatable {
    public var kind: DebugErrorKind
    public var service: Service?
    public var code: DebugCode?

    public init(_ error: Error) {
        guard let e = error as? ServiceError else { kind = .other; service = nil; code = nil; return }
        kind = DebugErrorKind(e)
        switch e {
        case .offline, .timedOut, .tls: service = nil; code = nil
        case .sessionExpired(let s), .badRequest(let s), .malformed(let s, _), .uncertain(let s): service = s; code = nil
        case .rejected(let s, let c, _): service = s; code = DebugCode(c)
        case .officialUnfinishedOrder: service = .lxt6; code = DebugCode(ServiceError.unfinishedOrderCode)
        }
    }
}

/// A short code a service answered (`4002`, `HTTP 502`): letters, digits, `-` and `_`, at most 12,
/// no run of 8 digits; anything else is `other`.
public struct DebugCode: Sendable, Equatable {
    public let text: String
    public static let other = "other"
    public init(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        let allowed = !s.isEmpty && s.count <= 12
            && s.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_" }
            && s.range(of: "[0-9]{8,}", options: .regularExpression) == nil
        text = allowed ? s : Self.other
    }
}

/// A value the log may need to compare (the same controller, washer or order?) but must not
/// show: written as `kind:` plus the first 6 hex of HMAC-SHA256(the log's own salt, value).
public struct DebugTag: Sendable, Equatable {
    public enum Kind: String, Sendable {
        /// A hot-water controller's machine id.
        case machine = "m"
        /// A washer's device id.
        case washer = "w"
        /// A laundry order id.
        case order = "o"
    }
    public let kind: Kind
    /// Only the sink reads it, to hash it. Upper-cased, so case variants hash the same.
    let value: String
    public init(_ kind: Kind, _ value: String) { self.kind = kind; self.value = value.uppercased() }
    public static func machine(_ id: String) -> DebugTag { DebugTag(.machine, id) }
}

/// One HTTP request (`HTTPLogEntry`), with the name, host, code and error reduced to known values.
public struct DebugHTTP: Sendable, Equatable {
    public enum Host: String, Sendable { case cas, portal, ecykt, lxt6, ujing, other }
    public enum Failure: String, Sendable {
        case blockedHost, transport, notHTTP, bodyTooLarge, offline, timedOut, tls, other
    }
    public var service: Service
    public var post: Bool
    public var host: Host
    public var name: DebugHTTPName
    public var status: Int?
    public var milliseconds: Int
    public var code: DebugCode?
    public var failure: Failure?

    public init(_ entry: HTTPLogEntry) {
        service = entry.service
        post = entry.method.uppercased() == "POST"
        switch entry.host.lowercased() {
        case SchoolEndpoints.casHost: host = .cas
        case SchoolEndpoints.portalHost: host = .portal
        case SchoolEndpoints.ecyktHost: host = .ecykt
        case _ where AllowedHosts.hotWater.contains(entry.host.lowercased()): host = .lxt6
        case _ where AllowedHosts.laundry.contains(entry.host.lowercased()): host = .ujing
        default: host = .other
        }
        name = DebugHTTPName(rawValue: entry.name) ?? .other
        status = entry.status
        milliseconds = entry.milliseconds
        code = entry.code.map(DebugCode.init)
        failure = entry.error.map { Failure(rawValue: $0) ?? .other }
    }
}

/// The request names the clients use (`HTTPRequest.logName`). A name not on the list (ecykt's
/// `lastPathComponent` fallback) is `other`.
public enum DebugHTTPName: String, Sendable, CaseIterable {
    case casLoginPage, casPublicKey, casLoginSubmit
    case csalogintoken, getSysBindCustInfo, loginBySysId, getSignData, getUserBalance, getRecordList
    case getBuildingInfo, getMeterStatus, service
    case getMyInfo, getMyECard
    case captcha, login, scanWasherCode, programInfo, createOrder, orderDetail, paymentMethods, paymentArguments, cancelOrder
    case startCheck, startWasher
    case authorize, settle, getUserMsg, getAreaInfoForApplests, getAreaForRoomApplests, getMachineMacAddress
    case feedback
    case other
}

/// The page that opened (`nav.open`). Both themes use the same names.
public enum DebugPage: String, Sendable, CaseIterable {
    /// `showerStopped`: the shower page's 上一次洗好了 face (开始下一次洗澡), each time it shows.
    case home, showerPage, showerStopped, showerDetail, laundry, washerSetup, cardRecords, cardTopUp, power, powerSetup
    case records, settings, account, dorm, theme, advanced, setupChecklist, onboarding, feedback, signIn
}

/// Where the page was opened from.
public enum DebugEntry: String, Sendable, CaseIterable {
    case homeButton, recents, cardRecords, settings, tab, liveActivity, widget, notification, intent
    case deepLink, pageEvent, setup, launch
    /// A page put back (the shower page popped while it must stay) or pages shown once a sheet went.
    case restore
    /// The first-run setup after 重置校日常.
    case reset
    /// Leaving 「先看看示例」 (去登录).
    case sample
    /// The account-switch alert's 去设置热水.
    case alert
    /// The expired-login line on home.
    case updateLine
    /// 常用洗衣机 saved, on to 洗衣.
    case setupDone
}
