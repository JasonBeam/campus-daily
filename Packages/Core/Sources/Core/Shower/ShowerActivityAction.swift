import Foundation

/// What the shower's Live Activity does for a record: the app's controller carries it out
/// with ActivityKit, so the decision itself is testable here.
public enum ShowerActivityAction: Sendable, Equatable {
    /// Nothing to show: end it now.
    case end
    /// The start is still being authorized: leave it as it is.
    case leave
    /// Water may be running: 洗澡中 with 结束并结算 (the unconfirmed line while the write is).
    case show(startedAt: Date, writeUnconfirmed: Bool)
    /// The end was sent and is settling.
    case settling(startedAt: Date)
    /// Settled: the result, then it goes after `dismissAfter`.
    case settled(startedAt: Date, minutes: Int, amountYuan: Decimal?, dismissAfter: TimeInterval)
    /// Failed: 「不确定」 stays on the lock screen for `dismissAfter`.
    case unconfirmed(startedAt: Date, dismissAfter: TimeInterval)

    public static let settledDismissal: TimeInterval = 4
    public static let unconfirmedDismissal: TimeInterval = 15 * 60

    public init(_ state: ShowerState, now: Date) {
        switch state.phase {
        case .idle: self = .end
        case .authorizing: self = .leave
        case .writePending where state.stateReviewRequired, .running where state.stateReviewRequired:
            // Stopped on the controller: that shower is over (the school settles it).
            self = .end
        case .writePending, .running:
            guard let started = state.startedAt else { self = .leave; return }
            self = .show(startedAt: started, writeUnconfirmed: state.phase == .writePending)
        case .closing, .settling:
            guard let started = state.startedAt else { self = .leave; return }
            self = .settling(startedAt: started)
        case .done:
            guard let started = state.startedAt else { self = .end; return }
            let minutes = state.minutes(until: state.endedAt ?? now) ?? 1
            // Only the platform receipt's amount; nil means not reported, never an estimate.
            self = .settled(startedAt: started, minutes: minutes, amountYuan: state.receipt?.amount?.yuan,
                            dismissAfter: Self.settledDismissal)
        case .failed:
            guard let started = state.startedAt else { self = .end; return }
            self = .unconfirmed(startedAt: started, dismissAfter: Self.unconfirmedDismissal)
        }
    }

    /// A result still lingering on the lock screen (「不确定」) ends now: the session is back on
    /// the timer, and a second activity beside the new 洗澡中 would contradict it.
    public var endsEarlierResult: Bool {
        if case .show = self { return true }
        return false
    }

    /// The activity stays on the lock screen for now.
    public var keepsActivity: Bool {
        switch self {
        case .end, .settled: return false
        case .leave, .show, .settling, .unconfirmed: return true
        }
    }
}
