import SwiftUI
import Core

/// One 最近 row in its card: symbol · title over 「when · detail」 · amount. Min height 56, 16 in
/// from the card's sides; the separator above it (not on the first) starts under the text.
struct ClearRecentRow: View {
    let item: RecentItem
    var separator = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.title3) private var symbolSize: CGFloat = 20

    var body: some View {
        VStack(spacing:0) {
            if separator { Divider().padding(.leading,48) }
            HStack(alignment:typeSize.isAccessibilitySize ? .firstTextBaseline : .center, spacing:12) {
                Image(systemName:item.symbol)
                    .font(.system(size:symbolSize))
                    .foregroundStyle(Theme.accentText)
                    .frame(width:symbolSize)
                    .accessibilityHidden(true)
                if typeSize.isAccessibilitySize {
                    VStack(alignment:.leading, spacing:4) { titles; amount }
                    Spacer(minLength:0)
                } else {
                    titles
                    Spacer(minLength:8)
                    amount
                }
            }
            .padding(.vertical,8).frame(minHeight:56)
            .padding(.horizontal,16)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children:.ignore)
        .accessibilityLabel([item.title, subtitle, item.spokenAmount].compactMap { $0 }.joined(separator:"，"))
    }

    private var titles: some View {
        VStack(alignment:.leading, spacing:2) {
            Text(item.title).font(.body).foregroundStyle(Theme.ink)
            Text(subtitle).font(.caption).foregroundStyle(Theme.ink2)
        }
        .fixedSize(horizontal:false, vertical:true)
    }

    @ViewBuilder private var amount: some View {
        if let text = item.amountText {
            Text(text).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var subtitle: String {
        [Theme.when(item.date), item.detail].compactMap { $0 }.joined(separator:" · ")
    }
}
