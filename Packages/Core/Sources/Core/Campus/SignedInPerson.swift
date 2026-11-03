import Foundation

/// Who is signed in: the card's stable `custunionid` and, after a form login, the account.
struct SignedInPerson: Sendable, Equatable {
    var cardUnionID: String?
    var account: String?

    enum Match: Sendable, Equatable { case same, different, unknown }

    /// The card decides when both sides have one; else the account; else nobody can tell.
    static func match(_ before: SignedInPerson?, cardUnionID: String?, account: String?) -> Match {
        guard let before else { return .unknown }
        if let a = before.cardUnionID, let b = cardUnionID { return a == b ? .same : .different }
        if let a = before.account, let b = account { return a == b ? .same : .different }
        return .unknown
    }
}
