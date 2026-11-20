import Foundation

/// 开始洗澡 below a zero balance. No balance (not read by this app for the person signed in
/// now) never blocks.
public enum ShowerBalanceGate {
    /// True when a start is refused for the balance.
    public static func blocks(_ balance: ShowerBalance?, allowsDebt: Bool) -> Bool {
        guard let balance, !allowsDebt else { return false }
        return balance.amount < .zero
    }
}
