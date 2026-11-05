import Foundation

/// How an event reads in the log: its name and `key=value` fields, every value a fixed word, a
/// number, a flag or a salted tag.
extension DebugEvent {
    public var name: String {
        switch self {
        case .showerAction: return "shower.action"
        case .showerPhase: return "shower.phase"
        case .showerRestore: return "shower.restore"
        case .showerNote: return "shower.note"
        case .bleConnect: return "ble.connect"
        case .bleProbe: return "ble.probe"
        case .bleAuthWrite: return "ble.authWrite"
        case .bleClose: return "ble.close"
        case .lxtAuthorize: return "lxt.authorize"
        case .lxtSettle: return "lxt.settle"
        case .laundryPhase: return "laundry.phase"
        case .laundryRequest: return "laundry.request"
        case .laundryOrder: return "laundry.order"
        case .laundryPayLaunch: return "laundry.payLaunch"
        case .schoolRefresh: return "school.refresh"
        case .schoolCredentialExpired: return "school.credentialExpired"
        case .schoolPasswordLogin: return "school.passwordLogin"
        case .schoolRenew: return "school.renew"
        case .ujingLogin: return "ujing.login"
        case .http: return "http"
        case .navOpen: return "nav.open"
        }
    }

    /// The fields, `tag` writing each salted tag.
    public func fields(tag: (DebugTag) -> String) -> String {
        var f = DebugFields()
        switch self {
        case .showerAction(let a):
            switch a {
            case .start(let m): f.word("start"); f["machine"] = tag(m)
            case .startNext(let m): f.word("startNext"); f["machine"] = tag(m)
            case .shortcutStart(let next): f.word("shortcutStart"); f.flag("next", next)
            case .finish: f.word("finish")
            case .review: f.word("review")
            case .dismiss: f.word("dismiss")
            case .cancelStart(let accepted): f.word("cancelStart"); f.flag("accepted", accepted)
            }
        case .showerPhase(let from, let to):
            f["from"] = from.rawValue
            f["to"] = to.phase.rawValue
            f.state(to)
        case .showerRestore(let saved, let restored, let unreadable):
            f["saved"] = saved?.rawValue ?? "none"
            f["restored"] = restored.rawValue
            if unreadable { f.word("unreadable") }
        case .showerNote(let d):
            f.word(d.name)
        case .bleConnect(let c):
            f["result"] = c.error?.rawValue ?? "ok"
            f["target"] = c.target.rawValue
            if let same = c.samePeripheral { f.flag("samePeripheral", same) }
        case .bleProbe(let frame, let verdict):
            f.frame(frame)
            f["verdict"] = verdict.rawValue
        case .bleAuthWrite(let w):
            f["out"] = String(ShowerFrames.authorizationLength)
            f.write(w, matchKey: "ack")
        case .bleClose(let w):
            f.write(w, matchKey: "consumption")
        case .lxtAuthorize(let step):
            switch step {
            case .sent: f.word("sent")
            case .notSent: f.word("notSent")
            case .ok(let length, let hex8): f.word("ok"); f["dataLength"] = String(length); f.flag("idHex8", hex8)
            case .failed(let e): f.word("failed"); f.error(e)
            }
        case .lxtSettle(let step):
            switch step {
            case .sent: f.word("sent")
            case .notSent: f.word("notSent")
            case .ok(let fen): f.word("ok"); f["fen"] = fen.map(String.init) ?? "unknown"
            case .failed(let e): f.word("failed"); f.error(e)
            }
        case .laundryPhase(let from, let to, let outcome):
            f["from"] = from.rawValue
            f["to"] = to.rawValue
            if let outcome { f["last"] = outcome.text }
        case .laundryRequest(let name, let outcome):
            f.word(name.rawValue)
            f.outcome(outcome)
        case .laundryOrder(let status, let module, let order):
            f["status"] = status.text
            if let module { f["moduleType"] = String(module) }
            if let order { f["order"] = tag(order) }
        case .laundryPayLaunch(let opened):
            f.flag("opened", opened)
        case .schoolRefresh(let o), .schoolRenew(let o):
            f.school(o)
        case .schoolCredentialExpired(let kind, let age, let alive):
            f["kind"] = kind.rawValue
            f["ageMinutes"] = age.map(String.init) ?? "unknown"
            if kind == .card { f["aliveMinutes"] = alive.map(String.init) ?? "unknown" }
        case .schoolPasswordLogin(let step):
            switch step {
            case .sent: f.word("sent")
            case .deferred(let r): f.word("deferred"); f["reason"] = r.rawValue
            case .skipped(let r): f.word("skipped"); f["reason"] = r.rawValue
            }
        case .ujingLogin(let o):
            f.outcome(o)
        case .http(let h):
            f.word(h.service.rawValue)
            f.word(h.post ? "POST" : "GET")
            f["host"] = h.host.rawValue
            f["name"] = h.name.rawValue
            if let status = h.status { f["status"] = String(status) }
            f["ms"] = String(h.milliseconds)
            if let code = h.code { f["code"] = code.text }
            if let failure = h.failure { f["error"] = failure.rawValue }
        case .navOpen(let page, let entry):
            f["page"] = page.rawValue
            f["from"] = entry.rawValue
        }
        return f.text
    }
}

/// Builds the space-separated fields of a line.
struct DebugFields {
    private var parts: [String] = []
    var text: String { parts.joined(separator: " ") }

    mutating func word(_ w: String) { parts.append(w) }
    subscript(key: String) -> String? {
        get { nil }
        set { if let newValue { parts.append("\(key)=\(newValue)") } }
    }
    mutating func flag(_ key: String, _ value: Bool) { parts.append("\(key)=\(value ? "yes" : "no")") }

    mutating func frame(_ frame: DebugFrame) {
        self["type"] = frame.kind.rawValue
        self["len"] = String(frame.length)
    }

    mutating func write(_ w: DebugWrite, matchKey: String) {
        switch w {
        case .notSent: word("notSent")
        case .failed(let e): word("failed"); self["device"] = e.rawValue
        case .replied(let frame, let matches): word("replied"); self.frame(frame); flag(matchKey, matches)
        }
    }

    mutating func error(_ e: DebugError) {
        self["kind"] = e.kind.rawValue
        if let s = e.service { self["service"] = s.rawValue }
        if let c = e.code { self["code"] = c.text }
    }

    mutating func outcome(_ o: DebugOutcome) {
        switch o {
        case .ok: word("ok")
        case .failed(let e): word("failed"); error(e)
        }
    }

    mutating func school(_ o: DebugSchoolOutcome) {
        switch o {
        case .ok: word("ok")
        case .notSignedIn: word("notSignedIn")
        case .leaseLost: word("leaseLost")
        case .interrupted: word("interrupted")
        case .needsLogin(let e): word("needsLogin"); error(e)
        case .failed(let e): word("failed"); error(e)
        }
    }

    mutating func state(_ s: DebugShowerState) {
        if let r = s.failure { self["failure"] = r.rawValue }
        if let d = s.deviceError { self["device"] = d.rawValue }
        if let k = s.errorKind { self["error"] = k.rawValue }
        if s.needsReview { word("needsReview") }
        if s.settleNotSent { word("settleNotSent") }
        if s.settleHeld { word("settleHeld") }
        if s.holdSettle { word("holdSettle") }
        if s.stateReviewRequired { word("stateReviewRequired") }
        if s.waitingForRelease { word("waitingForRelease") }
        if s.authorizationNotWritten { word("authorizationNotWritten") }
        if s.reviewing { word("reviewing") }
        if s.showerOver { word("showerOver") }
        if let n = s.notice { self["notice"] = n.rawValue }
        if let d = s.noticeDevice { self["noticeDevice"] = d.rawValue }
    }
}
