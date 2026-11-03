import SwiftUI
import Core

/// 2.4, 最近一次用水: the last settled shower, as home's 热水 tile has it: 已结算 · 11 分钟, when it
/// was settled (if kept), and the amount.
struct ClearShowerLastCard: View {
    let last: ShowerLastUse

    var body: some View {
        VStack(alignment:.leading, spacing:14) {
            Text("最近一次用水").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading, spacing:6) {
                    Text("已结算 · " + last.duration).font(.subheadline).monospacedDigit()
                    if let ended = last.ended {
                        Text(ended.formatted(date:.abbreviated, time:.shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength:8)
                if let amount = last.amount { Text(amount).font(.subheadline).monospacedDigit() }
            }
            .accessibilityElement(children:.combine)
        }
        .padding(18)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(NativeTheme.surface, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }
}
