import Foundation
import Core

typealias LaundryProgram = WasherProgram
typealias LaundrySnapshot = WasherSnapshot

/// View-facing names over the logic layer's laundry types (no logic).
extension WasherSnapshot {
    var deviceNo: String { info.deviceNo }
    var storeName: String { info.storeName }
    var programs: [WasherProgram] { info.programs }
    var status: Int { scan.status }
    var createOrderEnabled: Bool { scan.createOrderEnabled }
    var activeOrderId: String? { scan.activeOrderID }
}

extension WasherProgram {
    var workModelName: String { name }
    var time: Int { minutes }
}

extension LaundryCheckout {
    var orderId: String? { orderID ?? lastOutcome?.orderID }
    var programName: String { draft?.program.name ?? "洗衣" }
    var programId: Int? { draft?.program.id }
    var deviceId: String? { draft?.deviceID }
    /// The record still owns an order (anything but `none`).
    var inFlight: Bool { phase != .none }
}

/// What the last order was (kept after the engine clears the record, for the done panel).
struct LaundryLastOrder: Codable, Equatable {
    var orderID: String
    var program: WasherProgram
    var machineName: String
    var amount: Money?
}

/// Everything the laundry page and the home 洗衣 row read, from the model or DEBUG demo data.
/// Pure value: deriving a phase never triggers a request.
struct LaundryFacts {
    var configured = false
    var snapshot: WasherSnapshot?
    /// The engine's checkout record (any phase, including `none` with the last outcome).
    var record: LaundryCheckout?
    var busy = false
    var progress: String?
    var issue: String?
    var checkoutIssue: String?
    var loading = false
    var mayCreate = false
    var mayCancel = false
    /// U净 said the login ran out: 「重新登录 U净」 under the lines.
    var sessionExpired = false
    /// The last order's program/machine/amount, for the record after it was cleared.
    var lastOrder: LaundryLastOrder?

    @MainActor init(model: LaundryModel) {
        configured = model.configured; snapshot = model.snapshot; record = model.checkout
        busy = model.checkoutBusy; progress = model.checkoutProgress
        issue = model.issue; checkoutIssue = model.checkoutIssue; loading = model.loading
        mayCreate = model.mayCreate; mayCancel = model.mayCancel; lastOrder = model.lastOrder
        sessionExpired = model.sessionExpired
    }
    init() {}

    enum Unavailable: Equatable { case offline, broken, disabled }

    enum Phase: Equatable {
        /// No machine saved.
        case empty
        /// Machine saved, nothing read yet.
        case unknown
        case idle
        case inUse
        case unavailable(Unavailable)
        /// Order created, not paid. `payable` only while the engine allows a payment request.
        case unpaid(payable: Bool)
        /// Paid, machine not running yet (or no remaining time).
        case starting
        case running(end: Date)
        /// Result not confirmed. `failedStart` = order 52.
        case check(failedStart: Bool)
        /// Order 50 seen recently.
        case done
    }

    /// Recent terminal outcomes still worth showing (3 hours).
    private static let recentWindow: TimeInterval = 3 * 3600

    func phase(now: Date = Date()) -> Phase {
        guard configured else { return .empty }
        if let record {
            switch record.phase {
            case .none: break
            case .creating, .reconcile, .cancelling: return .check(failedStart:false)
            case .attention: return .check(failedStart:true)
            case .created:
                guard let order = record.order, order.isUnpaid else { return .check(failedStart:false) }
                return .unpaid(payable:record.canPay || record.canRepay(at:now))
            case .paying, .verifying:
                guard let order = record.order else { return .check(failedStart:false) }
                return order.isUnpaid ? .unpaid(payable:false) : .starting
            case .active:
                guard let order = record.order else { return .starting }
                if order.status.isWashing, let seconds = order.remainSeconds, seconds > 0 {
                    return .running(end:(record.orderReadAt ?? now).addingTimeInterval(TimeInterval(seconds)))
                }
                return .starting
            }
            if let outcome = record.lastOutcome, outcome.status.isDone, now.timeIntervalSince(outcome.at) < 30 * 60 {
                // 「刚刚洗完」 for half an hour after the order was seen finished.
                return snapshotPhase(doneFallback:true)
            }
        }
        return snapshotPhase(doneFallback:false)
    }

    private func snapshotPhase(doneFallback: Bool) -> Phase {
        guard let snapshot else { return doneFallback ? .done : .unknown }
        if doneFallback, snapshot.status == 0 { return .done }
        switch snapshot.status {
        case 8: return .unavailable(.offline)
        case 2: return .unavailable(.broken)
        case 7, 9: return .unavailable(.disabled)
        default: break
        }
        if snapshot.status == 0, snapshot.createOrderEnabled, snapshot.activeOrderId == nil { return .idle }
        if snapshot.status == 0, !snapshot.createOrderEnabled, snapshot.activeOrderId == nil { return .unavailable(.disabled) }
        return .inUse
    }

    /// Order id of a recently finished (50) order, for the once-per-order done panel.
    func doneOrderID(now: Date = Date()) -> String? {
        guard let outcome = record?.lastOutcome, record?.phase == LaundryPhase.none, outcome.status.isDone,
              now.timeIntervalSince(outcome.at) < Self.recentWindow else { return nil }
        return outcome.orderID
    }

    /// One-line note after a recent 51/53 (page shows idle plus this line).
    func outcomeNote(now: Date = Date()) -> String? {
        guard let outcome = record?.lastOutcome, record?.phase == LaundryPhase.none,
              now.timeIntervalSince(outcome.at) < Self.recentWindow else { return nil }
        switch outcome.status.code {
        case "51": return "上一笔订单付款超时，已经取消了。"
        case "53": return "上一笔订单已取消。"
        default: return nil
        }
    }

    /// The last order note when it belongs to the record's last outcome.
    private var finished: LaundryLastOrder? {
        guard let lastOrder, record?.inFlight != true, record?.lastOutcome?.orderID == lastOrder.orderID else { return nil }
        return lastOrder
    }

    var machine: String? {
        if let finished { return finished.machineName }
        guard let snapshot else { return record?.draft?.machineName }
        if let device = record?.deviceId, record?.inFlight == true, device != snapshot.deviceID { return record?.draft?.machineName }
        return snapshot.deviceNo
    }
    var store: String? { snapshot.map(\.storeName).flatMap { $0.isEmpty ? nil : $0 } }
    /// Program of the current record (for its duration).
    var recordProgram: WasherProgram? { record?.draft?.program ?? finished?.program }
    var amount: Decimal? {
        if let finished { return (finished.amount ?? finished.program.price).yuan }
        guard let record, record.inFlight else { return nil }
        return (record.order?.price ?? record.draft?.program.price)?.yuan
    }
}

enum LaundryFormat {
    static func spokenClock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour,.minute], from:date)
        return "\(parts.hour ?? 0) 点 \(parts.minute ?? 0) 分"
    }
    /// ceil(remaining / 60), never below 1 while running.
    static func minutesLeft(until end: Date, now: Date = Date()) -> Int {
        max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
    }
    static func machine(_ number: String) -> String { "\(number) 号机" }
    static func program(_ program: WasherProgram) -> String { "\(program.name) · \(program.minutes) 分钟" }
    static func spokenYuan(_ value: Decimal) -> String { Theme.yuan(value).dropFirst() + " 元" }
}
