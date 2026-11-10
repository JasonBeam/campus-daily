import Foundation

/// When the 「还在计时」 reminder counts from. Normally the water start (`ShowerState.startedAt`).
/// A session that comes back to the timer from the unsure face (a probe found water running
/// after an unconfirmed close) counts from that moment: its water start may be long past, and
/// a reminder counted from it would be due at once or skipped.
public enum ShowerReminderStart {
    /// For the record `next` after `old`; `current` is the start the reminder counts from now.
    /// Nil when no water may be flowing (or the controller showed the shower stopped).
    /// The moment saved in the record (`timerResumedAt`) wins, so a relaunch counts from it too.
    public static func next(_ next: ShowerState, after old: ShowerState, current: Date?, now: Date) -> Date? {
        // Stopped on the controller: that shower is over.
        guard next.mayBeFlowing, !next.stateReviewRequired else { return nil }
        if let resumed = next.timerResumedAt { return resumed }
        if old.phase == .failed { return now }
        return current ?? next.startedAt
    }
}
