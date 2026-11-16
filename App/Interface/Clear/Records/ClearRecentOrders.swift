import Foundation
import Core

/// The 订单 tab's own rows above the card's days: the last laundry order (open, or over within
/// the last hours), the shower still open, the last settled shower, and the showers a next use
/// kept (read-only: nothing on them settles or deletes).
struct ClearRecentOrders: Equatable {
    static let tabTitle = "订单"
    static let title = "最近订单"
    static let laundryTitle = "最近洗衣订单"
    static let showerOpenTitle = "当前热水记录"
    static let showerSettledTitle = "最近热水结算"
    static let settled = "热水已结算"
    static let noAmount = "金额未返回"
    static let retainedTitle = ShowerRetainedText.Clear.sectionTitle
    static let retainedFooter = ShowerRetainedText.Clear.footer

    enum Section: Equatable { case laundry, showerOpen, showerSettled, showerRetained }

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
    var retained: ShowerRetainedSummary?

    /// Finished orders stay listed this long (as the laundry page's line).
    private static let recentWindow: TimeInterval = 3 * 3600

    init(data: HomeData, laundry facts: LaundryFacts, retained: ShowerRetainedSummary? = nil, now: Date = Date()) {
        self.retained = retained
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
         showerSettled.map { _ in Section.showerSettled }, retained.map { _ in Section.showerRetained }].compactMap { $0 }
    }

    /// Two lines per kept shower, newest first: the start time, then 「水控 编号 · 原因」 (the dorm's own controller left out).
    func retainedLines(time: (Date) -> String = { ShowerRetainedText.time($0) }) -> [ShowerRetainedText.Line] {
        retained.map { ShowerRetainedText.lines($0, reason:ShowerRetainedText.Clear.reason, time:time) } ?? []
    }

    /// The id a section is scrolled to by (`ClearNavigator.recordsScroll`).
    static func scrollID(_ section: Section) -> String {
        switch section {
        case .laundry: "recordsLaundry"
        case .showerOpen: "recordsShowerOpen"
        case .showerSettled: "recordsShowerSettled"
        case .showerRetained: "recordsRetainedShowers"
        }
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
