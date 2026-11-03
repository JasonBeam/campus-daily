import Foundation

/// 退出 U净: the login and its number go; the install's mobile id, the saved machines and the
/// selected machine stay, so signing in again finds them.
public enum UjingSignOut {
    public enum Refusal: Error, Sendable, Equatable {
        /// A laundry order is unfinished: it needs this login to be checked.
        case orderOpen
        /// A machine read or an order step is running.
        case busy
    }

    public struct Outcome: Sendable, Equatable {
        /// The last-order note belonged to this account and went.
        public var forgotLastOrder: Bool
        /// The stored finished outcome went with it.
        public var clearedCheckout: Bool
    }

    public static func refusal(orderOpen: Bool, busy: Bool) -> Refusal? {
        if orderOpen { return .orderOpen }
        return busy ? .busy : nil
    }

    /// The line under the section while the button is greyed. A running step needs no reason:
    /// it is over in a moment.
    public static func footer(_ refusal: Refusal?) -> String? {
        refusal == .orderOpen ? "还有一笔洗衣订单没处理完，处理完才能退出。" : nil
    }

    /// Writes the signed-out login. The finished order's outcome and the last-order note go too
    /// (`LaundryCheckout.clearsLastOrder`). Throws `Refusal` with an order open, and the vault's
    /// error when the login can't be written (then nothing else changed).
    public static func perform(vault: LaundryVault, preferences: any PreferenceStorage,
                               checkout: LaundryCheckout?) throws -> Outcome {
        if let refusal = refusal(orderOpen: (checkout?.phase ?? .none) != .none, busy: false) { throw refusal }
        let item = try vault.accountItem()
        let forget = LaundryCheckout.clearsLastOrder(record: checkout, signedInAs: nil, stored: item?.account?.id)
        try vault.saveAccountItem(item.map { UjingAccountItem(mobileID: $0.mobileID) })
        var cleared = false
        if forget {
            if checkout?.lastOutcome != nil, (try? vault.saveCheckout(nil)) != nil { cleared = true }
            preferences.set(nil, forKey: PreferenceKey.laundryLastOrder)
        }
        return Outcome(forgotLastOrder: forget, clearedCheckout: cleared)
    }
}
