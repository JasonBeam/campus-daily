import Foundation

public enum LaundryReminderAction: Equatable {
    case ignore, clear, completed
    case estimate(TimeInterval)
}

public enum LaundryReminderPolicy {
    public static func action(status: String, remaining: Int?, observedAt: TimeInterval, now: TimeInterval,
                              tracked: Bool, alreadyReminded: Bool, recentOrder: Bool = false) -> LaundryReminderAction {
        guard observedAt <= now + 5, now - observedAt < 60 else { return .ignore }
        // A recent, confirmed completion also needs an alert when no running countdown was observed.
        if status == "50" { return recentOrder && !alreadyReminded ? .completed : .ignore }
        if ["51","52","53"].contains(status) {
            guard tracked else { return .ignore }
            return .clear
        }
        guard ["21","22","24","29","30","35","40"].contains(status),
              let seconds = remaining, (0...86400).contains(seconds), !alreadyReminded,
              seconds > 0 || ["30","40"].contains(status) else { return .ignore }
        return .estimate(observedAt + Double(seconds))
    }
}
