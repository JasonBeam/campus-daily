import Foundation

/// When the 「衣服洗好了」 reminder goes off for the open order. Pure: the app schedules what
/// `step` returns.
public enum LaundryDoneReminder {
    /// The reminder for one order.
    public struct Plan: Sendable, Equatable {
        public var orderID: String
        public var end: Date
        public init(orderID: String, end: Date) { self.orderID = orderID; self.end = end }
    }

    public enum Step: Sendable, Equatable {
        /// Remind at the plan's end (a request already set for it stays, see `isScheduled`).
        case schedule(Plan)
        /// Whatever is set stays: the result isn't confirmed, or the end isn't known yet.
        case keep
        /// Nothing to remind: done, cancelled, failed to start, unpaid or no order.
        case cancel
    }

    /// A set request moves only when its end is this many seconds off.
    public static let tolerance: TimeInterval = 30

    /// `scheduled` is the request set now. A washing read gives the exact end and replaces a
    /// fallback; while paid and not washing yet the fallback is payment time + program length,
    /// unless a request for this order is already set (which may be an exact one).
    public static func step(_ c: LaundryCheckout?, scheduled: Plan?, now: Date) -> Step {
        guard let c else { return .cancel }
        switch c.phase {
        case .none, .attention:
            // Order 52: the machine never ran, so the clothes won't be done.
            return .cancel
        case .creating, .reconcile, .cancelling:
            return .keep
        case .created:
            return c.order?.isUnpaid == true ? .cancel : .keep
        case .paying, .verifying:
            guard let order = c.order else { return .keep }
            return order.isUnpaid ? .cancel : waiting(c, scheduled: scheduled)
        case .active:
            if let order = c.order, order.status.isWashing, let seconds = order.remainSeconds, seconds > 0 {
                guard let id = c.orderID else { return .keep }
                return .schedule(Plan(orderID: id, end: (c.orderReadAt ?? now).addingTimeInterval(TimeInterval(seconds))))
            }
            return waiting(c, scheduled: scheduled)
        }
    }

    /// `plan` is already set as `scheduled` (same order, end within `tolerance`).
    public static func isScheduled(_ plan: Plan, as scheduled: Plan?) -> Bool {
        guard let scheduled, scheduled.orderID == plan.orderID else { return false }
        return abs(scheduled.end.timeIntervalSince(plan.end)) < tolerance
    }

    private static func waiting(_ c: LaundryCheckout, scheduled: Plan?) -> Step {
        guard let id = c.orderID, let end = LaundryFollowUp.expectedEnd(c) else { return .keep }
        // The request set for this order (maybe an exact end) stays, and the app keeps it as the
        // plan to add again after a resync.
        if let scheduled, scheduled.orderID == id { return .schedule(scheduled) }
        return .schedule(Plan(orderID: id, end: end))
    }
}
