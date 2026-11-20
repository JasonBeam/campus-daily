import Foundation

/// A campus-card balance the school answered for the card this login is bound to, in one
/// refresh, stamped with who was signed in when that refresh began (`SchoolSession.personStamp`).
/// Unlike the home snapshot (shared with the widget, kept across runs), only this decides
/// whether hot water may start below zero.
public struct CardBalanceRead: Sendable, Equatable {
    public var amount: Money
    public var readAt: Date
    /// `SchoolSession.personStamp()` when the refresh began.
    public var person: Int

    public init(amount: Money, readAt: Date, person: Int) {
        self.amount = amount; self.readAt = readAt; self.person = person
    }

    /// Still the signed-in person's.
    // Red-phase stub: never counts.
    public func counts(forPerson current: Int, signedIn: Bool) -> Bool {
        false
    }
}
