import Foundation

/// A paid order that is not washing with a known end yet (paid and waiting to start, starting,
/// or 40 without a remaining time). Nothing else reads it again: the payment poll has stopped
/// and the end-of-wash read needs an end. So the app reads it again on a short timer for a few
/// minutes while it is in front, and the done reminder is set from the payment time until a
/// washing read gives the real end.
public enum LaundryFollowUp {
    /// Seconds between re-reads.
    public static let interval: TimeInterval = 45
    /// Re-reads stop this long after the order was first seen waiting (or after a 立刻洗衣 start request).
    public static let window: TimeInterval = 5 * 60

    /// Seconds until the next re-read (0 = now), or nil when none is due: not a waiting paid
    /// order, or the window is used up. `lastAttempt` is the app's last try (a failed read leaves
    /// `orderReadAt` unchanged).
    public static func nextRead(_ c: LaundryCheckout, lastAttempt: Date?, now: Date) -> TimeInterval? {
        guard c.phase == .active, let waiting = c.waitingSince else { return nil }
        // 立刻洗衣: the window runs again from the start request.
        let since = max(waiting, c.start?.requestedAt ?? waiting)
        let last = [c.orderReadAt, lastAttempt].compactMap { $0 }.max() ?? since
        let next = max(last, since).addingTimeInterval(interval)
        guard next.timeIntervalSince(since) <= window else { return nil }
        return max(0, next.timeIntervalSince(now))
    }

    /// When the wash would end had it started as soon as the payment was seen: the done
    /// reminder's time until a washing read gives the end.
    public static func expectedEnd(_ c: LaundryCheckout) -> Date? {
        guard c.phase == .active, let paid = c.paidAt, let minutes = c.draft?.program.minutes, minutes > 0 else { return nil }
        return paid.addingTimeInterval(TimeInterval(minutes * 60))
    }
}
