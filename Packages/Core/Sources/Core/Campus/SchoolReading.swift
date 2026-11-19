import Foundation

/// What one school read found. Campus only reports; the snapshot refresher turns this into
/// the shared home snapshot.
public struct SchoolReading: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case ok
        /// The user must sign in again (ecykt dead and no silent re-exchange possible/working).
        case needsLogin(ServiceError)
        /// The liveness check failed for another reason (offline, …).
        case failed(ServiceError)
        case notSignedIn
        /// The saved password was changed while this read ran (保存密码, 重新输入密码), or the
        /// Keychain refused a write or a read: nothing is known about the login. Not an error to
        /// show: the stored numbers stay as they are and the next refresh goes ahead.
        case interrupted
        /// This read lost the refresh lease (it ran out while the app was suspended, the other
        /// process took it, or a sign-out removed it) and stopped. Not an error: the snapshot
        /// shows what is stored, which the other process may be updating.
        case leaseLost
    }
    public var outcome: Outcome
    /// When the liveness check answered (or failed).
    public var checkedAt: Date
    /// Balance read; nil when it was not attempted.
    public var balance: Result<Money, ServiceError>?
    /// Room meter read; nil when no meter is bound or it was not attempted.
    /// `.success(nil)` = no meter at the saved node.
    public var meter: Result<Meter?, ServiceError>?
    /// The card's recent records; nil when not attempted.
    public var activity: Result<CardActivity, ServiceError>?
    public var roomLabel: String?
    /// When balance and meter answered.
    public var readAt: Date?
    /// No meter is bound (none saved, or one bound to the campus node by an older build): the
    /// stored electricity reading belongs to no meter and is cleared.
    public var noMeter: Bool

    public init(outcome: Outcome, checkedAt: Date, balance: Result<Money, ServiceError>? = nil,
                meter: Result<Meter?, ServiceError>? = nil, roomLabel: String? = nil, readAt: Date? = nil,
                noMeter: Bool = false) {
        self.outcome = outcome; self.checkedAt = checkedAt; self.balance = balance; self.meter = meter
        self.roomLabel = roomLabel; self.readAt = readAt; self.noMeter = noMeter
    }
}
