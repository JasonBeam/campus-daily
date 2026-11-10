import SwiftUI
import Core

/// 上次热水 · 已结算 on home: when the last shower was settled, and its amount.
struct ClearLastShowerCard: View {
    let ended: Date
    let cost: Decimal?

    var body: some View {
        HStack(spacing:12) {
            VStack(alignment:.leading, spacing:5) {
                Text("上次热水 · 已结算").font(.subheadline).foregroundStyle(Theme.ink)
                Text(ClearBalanceText.dateTime(ended)).font(.caption).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength:8)
            if let cost {
                Text(ClearBalanceText.currency(cost)).font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(16)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
        .accessibilityElement(children:.combine)
    }
}
