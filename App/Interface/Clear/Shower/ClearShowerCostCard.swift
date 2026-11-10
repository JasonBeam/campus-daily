import SwiftUI
import Core

/// 2.3, the 本次费用 card: the settled amount, 「结算后显示」 before it.
struct ClearShowerCostCard: View {
    @EnvironmentObject private var shower: ShowerModel
    /// Nil: no session to show (ready to start).
    let phase: ShowerPagePhase?
    let live: Bool

    private var page: ShowerPage? { shower.page.page }

    var body: some View {
        VStack(alignment:.leading, spacing:14) {
            ClearShowerCostRow(label:ClearShowerText.cost) { cost }
        }
        .padding(18)
        .background(NativeTheme.surface, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }

    @ViewBuilder private var cost: some View {
        switch phase {
        case .done?:
            // Only the platform's amount is ever shown.
            if let amount = page?.amount {
                Text(ClearBalanceText.currency(amount.yuan)).font(.title2.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("\(amount.yuanText) 元")
            } else {
                missing
            }
        case nil where live && shower.state.phase == .done:
            if let cost = shower.lastCost {
                Text(ClearBalanceText.currency(cost)).font(.title2.weight(.semibold)).monospacedDigit()
            } else {
                missing
            }
        default:
            Text(ClearShowerText.costLater).font(.subheadline)
        }
    }

    private var missing: some View {
        Text(ClearShowerText.costMissing).font(.subheadline).foregroundStyle(.secondary)
    }
}
