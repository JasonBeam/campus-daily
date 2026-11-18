import Foundation

/// The automatic check of the controller while the app is in front: a read-only `AA` probe over a
/// record whose water may run and that waits for nothing, or over a close whose outcome is unknown
/// until this controller is seen stopped; at most once per `interval`, with no limit on attempts.
/// It never authorizes, closes or settles (`ShowerEngine.autoReview`, `ShowerEngine.readOnlyAllows`).
public enum ShowerAutoReview {
    /// How often the foreground loop looks.
    public static let tick: Duration = .seconds(5)
    /// The least time between two attempts, counted from an attempt's start (a failed one too).
    public static let interval: TimeInterval = 30

    /// Water may run (`writePending`, `running`) and nothing waits on the record: not a probe
    /// under way, not a session the controller showed stopped, not one the next use found in use,
    /// not an authorization that provably never reached the controller (a probe would end that
    /// record; the user does that). A failed record only after an unsure close (answered busy, no
    /// end data, or a relaunch mid-close), until a check saw this controller idle (`closeStopSeen`).
    public static func eligible(_ s: ShowerState) -> Bool {
        if s.phase == .failed {
            return s.failure?.reason.isUnsureClose == true && !s.closeStopSeen && !s.reviewing && !s.waitingForRelease
        }
        return (s.phase == .writePending || s.phase == .running)
            && !s.reviewing && !s.stateReviewRequired && !s.waitingForRelease && !s.authorizationNotWritten
    }

    /// The interval has passed since the last attempt (either way, so a clock set back does not
    /// make it run every tick).
    public static func due(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return abs(now.timeIntervalSince(lastAttempt)) >= interval
    }
}
