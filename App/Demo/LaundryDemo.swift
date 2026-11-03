#if DEBUG
import SwiftUI
import Core

// MARK: - DEBUG demo (campusdaily://demo/laundry/<state>); fake data, never places an order.

struct LaundryDemo {
    enum Kind: String {
        case idle, busy, unpaid, run, check, inuse, offline, broken, disabled, empty, done, confirm, cancel
    }
    enum InitialSheet { case confirm, cancel }
    var facts: LaundryFacts
    var sheet: InitialSheet?
    var panel: SettlementResult?
    var notify = true

    static func handle(_ url: URL) -> LaundryDemo? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "laundry" else { return nil }
        return make(Kind(rawValue:parts.count > 1 ? parts[1] : "idle") ?? .idle)
    }

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
        }
        return demo
    }

    static let programs: [WasherProgram] = [(1,"标准洗",45,400),(2,"快洗",30,300),(3,"大物洗",60,500),(4,"单脱水",6,100)].map {
        WasherProgram(id:$0.0, name:$0.1, minutes:$0.2, price:Money(fen:$0.3))
    }

    static func snapshot(status: Int, active: String? = nil) -> WasherSnapshot {
        WasherSnapshot(qrCode:"demo",
                       scan:WasherScan(deviceID:"demo-washer", moduleType:7, status:status, createOrderEnabled:status == 0, activeOrderID:active),
                       info:WasherInfo(deviceID:"demo-washer", deviceNo:"3", typeName:"波轮洗衣机", storeName:"4 栋洗衣房",
                                       storeID:"demo-store", deviceTypeID:1, moduleType:7, programs:programs),
                       fetchedAt:Date())
    }

    static func record(stage: LaundryPhase, status: String?, paid: Bool, remain: Int?, created: Date, now: Date) -> LaundryCheckout {
        let draft = LaundryDraft(deviceID:"demo-washer", qrCode:"demo", machineName:"3", program:programs[0],
                                 request:OrderRequest(deviceID:"demo-washer", deviceTypeID:1, storeID:"demo-store", programID:1))
        var record = LaundryCheckout(phase:stage, draft:draft, createdAt:created)
        if let status {
            record.orderID = "demo1"
            record.order = LaundryOrder(id:"demo1", deviceID:"demo-washer", status:LaundryOrderStatus(status), paid:paid,
                                        remainSeconds:remain, programID:1, price:Money(fen:400),
                                        countDown:status == "10" ? 600 : nil)
            record.orderReadAt = now
        }
        if stage == .none, let status {
            record = LaundryCheckout(lastOutcome:LaundryOutcome(orderID:"demo1", status:LaundryOrderStatus(status), at:now))
        }
        return record
    }
}
#endif
