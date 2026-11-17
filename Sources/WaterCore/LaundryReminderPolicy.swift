import Foundation

public enum LaundryReminderAction: Equatable {
    case ignore, clear
    case estimate(TimeInterval)
}

public enum LaundryReminderPolicy {
    public static func recordDelivered(_ key: String, in keys: [String]) -> [String] {
        Array((keys.filter { $0 != key } + [key]).suffix(64))
    }
    public static func recordDeliveryTime(_ time: TimeInterval, for key: String,
                                          keys: [String], dates: [String: TimeInterval]) -> (keys: [String], dates: [String: TimeInterval]) {
        let kept = recordDelivered(key,in:keys)
        var updated = dates.filter { kept.contains($0.key) }
        if updated[key] == nil { updated[key] = time }
        return (kept,updated)
    }
    public static func action(status: String, remaining: Int?, observedAt: TimeInterval, now: TimeInterval,
                              tracked: Bool, alreadyReminded: Bool, deadline: TimeInterval? = nil) -> LaundryReminderAction {
        guard observedAt <= now + 5, now - observedAt < 60 else { return .ignore }
        // Completion can arrive early and retain a stale remaining time.
        // Keep the timer previously scheduled from the running order.
        if status == "50" { return .ignore }
        if ["51","52","53"].contains(status) {
            guard tracked else { return .ignore }
            return .clear
        }
        guard ["21","22","24","29","30","35","40"].contains(status),
              let seconds = remaining, (0...86400).contains(seconds), !alreadyReminded,
              seconds > 0 || ["30","40"].contains(status) else { return .ignore }
        return .estimate(deadline ?? observedAt + Double(seconds))
    }
}
