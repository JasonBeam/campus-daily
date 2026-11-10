import SwiftUI
import Core

// MARK: - Demo (campusdaily://demo/laundry/<state>, DEBUG) and the sample mode's washer (`idle`);
// fake data, never places an order.

struct LaundryDemo {
    enum Kind: String {
        case idle, busy, unpaid, run, check, inuse, offline, broken, disabled, empty, done, confirm, cancel
        // 立刻洗衣 (fake records; nothing is started).
        case confirmNow = "confirm-now", nowUnpaid = "now-unpaid", nowReady = "now-ready", nowChecking = "now-checking"
        case nowSent = "now-sent", nowUncertain = "now-uncertain", nowUnsupported = "now-unsupported"
        case nowExpired = "now-expired", nowRefused = "now-refused"
        case nowAccount = "now-account", nowPrice = "now-price"
    }
    enum InitialSheet { case confirm, cancel }
    var facts: LaundryFacts
    var sheet: InitialSheet?
    var panel: SettlementResult?
    var notify = true
    /// The pay sheet opens on 立刻洗衣 (screenshots only; the live sheet always opens on 正常洗衣).
    var immediate = false

    #if DEBUG
    static func handle(_ url: URL) -> LaundryDemo? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "laundry" else { return nil }
        return make(Kind(rawValue:parts.count > 1 ? parts[1] : "idle") ?? .idle)
    }
    #endif

    static func make(_ kind: Kind, now: Date = Date()) -> LaundryDemo {
        var facts = LaundryFacts()
        facts.configured = true
        facts.snapshot = snapshot(status:0)
        facts.mayCreate = true
        var demo = LaundryDemo(facts:facts)
        switch kind {
        case .idle: break
        case .confirm: demo.sheet = .confirm
        case .busy:
            demo.facts.busy = true; demo.facts.mayCreate = false; demo.facts.progress = "正在打开支付宝…"
        case .unpaid, .cancel:
            demo.facts.snapshot = snapshot(status:11, active:"demo1")
            demo.facts.record = record(stage:.created, status:"10", paid:false, remain:nil, created:now.addingTimeInterval(-60), now:now)
            demo.facts.mayCreate = false; demo.facts.mayCancel = true
            if kind == .cancel { demo.sheet = .cancel }
        case .run:
            demo.facts.snapshot = snapshot(status:1, active:"demo1")
            demo.facts.record = record(stage:.active, status:"40", paid:true, remain:18 * 60 - 30,
                                       created:now.addingTimeInterval(-27 * 60), now:now)
            demo.facts.mayCreate = false
        case .check:
            demo.facts.record = record(stage:.creating, status:nil, paid:false, remain:nil, created:now.addingTimeInterval(-12 * 60), now:now)
            demo.facts.mayCreate = false
        case .inuse: demo.facts.snapshot = snapshot(status:1); demo.facts.mayCreate = false
        case .offline: demo.facts.snapshot = snapshot(status:8); demo.facts.mayCreate = false
        case .broken: demo.facts.snapshot = snapshot(status:2); demo.facts.mayCreate = false
        case .disabled: demo.facts.snapshot = snapshot(status:9); demo.facts.mayCreate = false
        case .empty: demo.facts = LaundryFacts()
        case .done:
            demo.facts.record = record(stage:.none, status:"50", paid:true, remain:nil, created:now.addingTimeInterval(-50 * 60), now:now)
            demo.panel = .laundryDone(amount:Decimal(string:"4.00"), detail:"标准洗 · 45 分钟 · 3 号机")
        case .confirmNow:
            demo.sheet = .confirm; demo.immediate = true
        case .nowUnpaid:
            demo.facts.snapshot = snapshot(status:11, active:"demo1")
            var r = record(stage:.created, status:"10", paid:false, remain:nil, created:now.addingTimeInterval(-60), now:now)
            r.immediate = true
            demo.facts.record = r
            demo.facts.mayCreate = false; demo.facts.mayCancel = true
        case .nowReady, .nowChecking, .nowSent, .nowUncertain, .nowUnsupported, .nowExpired, .nowRefused, .nowAccount, .nowPrice:
            demo.facts.snapshot = snapshot(status:11, active:"demo1")
            var r = record(stage:.active, status:"20", paid:true, remain:nil, created:now.addingTimeInterval(-2 * 60), now:now)
            r.immediate = true
            let at = now.addingTimeInterval(-20)
            switch kind {
            case .nowChecking: r.checkingStart = true
            case .nowSent: r.start = .accepted(at:at)
            case .nowUncertain: r.start = .pending(at:at)
            case .nowUnsupported: r.start = .blocked(.unsupported)
            case .nowAccount: r.start = .blocked(.account)
            case .nowPrice: r.start = .blocked(.price)
            case .nowExpired:
                r = record(stage:.active, status:"20", paid:true, remain:nil, created:now.addingTimeInterval(-14 * 60), now:now)
                r.immediate = true; r.start = .blocked(.expired)
            // A made-up refusal, two lines long (synthetic; not U净's words).
            case .nowRefused: r.start = .refused(message:"示例：设备正在自检，请稍后在 U净 App 内重新操作启动", at:at)
            default: break
            }
            demo.facts.record = r
            demo.facts.mayCreate = false
        }
        return demo
    }

    static var programs: [WasherProgram] { SampleData.washerPrograms }

    static func snapshot(status: Int, active: String? = nil) -> WasherSnapshot {
        SampleData.washerSnapshot(status:status, active:active)
    }

    static func record(stage: LaundryPhase, status: String?, paid: Bool, remain: Int?, created: Date, now: Date) -> LaundryCheckout {
        SampleData.laundryCheckout(stage:stage, status:status, paid:paid, remain:remain, created:created, now:now)
    }
}
