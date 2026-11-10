import Foundation
import Core

/// The 订单 tab's own rows above the card's days: the last laundry order (open, or over within
/// the last hours), the shower still open, and the last settled shower.
struct ClearRecentOrders: Equatable {
    static let tabTitle = "订单"
    static let title = "最近订单"
    static let laundryTitle = "最近洗衣订单"
    static let showerOpenTitle = "当前热水记录"
    static let showerSettledTitle = "最近热水结算"
    static let settled = "热水已结算"
    static let noAmount = "金额未返回"

    enum Section: Equatable { case laundry, showerOpen, showerSettled }

    struct Laundry: Equatable {
        let title: String
        let program: String
        let amount: Decimal?
    }

    struct Settled: Equatable {
        let date: Date
        let amount: Decimal?
    }

    var laundry: Laundry?
    var showerOpen: ClearOpenItem?
    var showerSettled: Settled?

    /// Finished orders stay listed this long (as the laundry page's line).
    private static let recentWindow: TimeInterval = 3 * 3600

    init(data: HomeData, laundry facts: LaundryFacts, now: Date = Date()) {
        if data.laundryEnabled { laundry = Self.laundry(facts, now:now) }
        showerOpen = ClearOpenItem.shower(data.shower)
        let shower = data.recentActivities
            .filter { if case .shower = $0.kind { return true }; return false }
            .max { $0.date < $1.date }
        showerSettled = shower.map { Settled(date:$0.date, amount:$0.amount?.yuan) }
    }

    /// The sections there are rows for, in the tab's order.
    var sections: [Section] {
        [laundry.map { _ in Section.laundry }, showerOpen.map { _ in Section.showerOpen },
         showerSettled.map { _ in Section.showerSettled }].compactMap { $0 }
    }

    private static func laundry(_ facts: LaundryFacts, now: Date) -> Laundry? {
        guard let record = facts.record else { return nil }
        let program = facts.recordProgram?.name ?? record.programName
        if record.inFlight {
            return Laundry(title:record.order?.status.label ?? "订单待核对", program:program, amount:facts.amount)
        }
        guard let outcome = record.lastOutcome, now.timeIntervalSince(outcome.at) < recentWindow else { return nil }
        return Laundry(title:outcome.status.label, program:program, amount:facts.amount)
    }
}
