import Foundation

/// What a recharge tops up: the campus card or the dorm's electricity. Payment happens inside the
/// school's web page; the app only prepares its session.
public enum RechargeKind: String, Sendable, Codable, Equatable {
    case card, electricity
}
