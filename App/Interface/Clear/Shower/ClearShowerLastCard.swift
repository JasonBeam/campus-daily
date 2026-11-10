import SwiftUI
import Core

/// 2.4, 最近一次用水: the last settled shower: 已结算, when it was settled (if kept), and the
/// amount in the system's currency style.
struct ClearShowerLastCard: View {
    let last: ShowerLastUse

    var body: some View {
        VStack(alignment:.leading, spacing:14) {
            Text(ClearShowerText.lastUse).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading, spacing:6) {
                    Text(ClearShowerText.lastUseSettled).font(.subheadline)
                    if let ended = last.ended {
                        Text(ended.formatted(date:.abbreviated, time:.shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength:8)
                if let cost = last.cost { Text(ClearBalanceText.currency(cost)).font(.subheadline).monospacedDigit() }
            }
            .accessibilityElement(children:.combine)
        }
        .padding(18)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(NativeTheme.surface, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }
}
