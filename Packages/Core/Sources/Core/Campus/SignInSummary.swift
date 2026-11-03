import Foundation

public struct SignInSummary: Sendable, Equatable {
    /// A different person than the one signed in before: the old dorm, meter and saved
    /// account were cleared first (the app clears its own per-person data too).
    public var switchedAccount: Bool
    /// Someone was signed in, and neither the card nor the account shows whether this is them:
    /// their dorm and meter were not kept (unless the new dorm is the same room), and the app
    /// drops what it keeps per person as for a switch.
    public var previousPersonUnconfirmed: Bool
    /// The previous dorm or meter is gone (removed, or replaced by another dorm). False when
    /// the same room was read again and both were kept, or there was none.
    public var dormAndMeterCleared: Bool
    public init(switchedAccount: Bool = false, previousPersonUnconfirmed: Bool = false, dormAndMeterCleared: Bool = false) {
        self.switchedAccount = switchedAccount
        self.previousPersonUnconfirmed = previousPersonUnconfirmed; self.dormAndMeterCleared = dormAndMeterCleared
    }
}
