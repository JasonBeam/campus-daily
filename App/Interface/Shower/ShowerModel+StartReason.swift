import Foundation
import Core

extension ShowerModel {
    /// The line under a greyed-out 开始洗澡 for `block` (`ShowerStartBlock.text(clear:balance:)`):
    /// the balance's says what the card owes.
    func startReason(_ block: ShowerStartBlock?, clear: Bool) -> String? {
        block?.text(clear:clear, balance:reasonBalance)
    }

    /// The balance the reason goes by (a DEBUG demo's: -¥0.50).
    private var reasonBalance: Money? {
        #if DEBUG
        if demoStartBlock == .balanceNegative { return HomeView.ShowerPageDemo.owed }
        #endif
        return balance?.amount
    }
}
