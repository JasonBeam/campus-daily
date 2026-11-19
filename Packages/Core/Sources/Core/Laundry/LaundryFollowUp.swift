import Foundation

/// A paid order that is not washing with a known end yet (paid and waiting to start, starting,
/// or 40 without a remaining time): the done reminder is set from the payment time until a
/// washing read gives the real end. The reads themselves are `LaundryForegroundPoll`'s.
public enum LaundryFollowUp {
    /// When the wash would end had it started as soon as the payment was seen: the done
    /// reminder's time until a washing read gives the end.
    public static func expectedEnd(_ c: LaundryCheckout) -> Date? {
        guard c.phase == .active, let paid = c.paidAt, let minutes = c.draft?.program.minutes, minutes > 0 else { return nil }
        return paid.addingTimeInterval(TimeInterval(minutes * 60))
    }
}
