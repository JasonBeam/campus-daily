import SwiftUI
import Core

/// A row of 记录's day groups: symbol · title over 「12:05 · 商户」 · amount (± as 最近 has it).
struct ClearRecordRow: View {
    let item: RecentItem
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.title3) private var iconColumn: CGFloat = 28

    var body: some View {
        // Accessibility sizes: the amount goes under the titles.
        HStack(alignment:typeSize.isAccessibilitySize ? .firstTextBaseline : .center, spacing:12) {
            RowIcon(symbol:item.symbol).frame(width:iconColumn)
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading, spacing:4) { titles; amount }
                Spacer(minLength:0)
            } else {
                titles
                Spacer(minLength:8)
                amount
            }
        }
        .padding(.vertical,4)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel([item.title, subtitle, item.spokenAmount].compactMap { $0 }.joined(separator:"，"))
    }

    private var titles: some View {
        VStack(alignment:.leading, spacing:2) {
            Text(item.title).font(.body).foregroundStyle(Color.primary)
            Text(subtitle).font(.caption).foregroundStyle(Color.secondary)
        }
        .fixedSize(horizontal:false, vertical:true)
    }

    @ViewBuilder private var amount: some View {
        if let text = item.amountText {
            Text(text).font(.body).monospacedDigit().foregroundStyle(Color.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var subtitle: String {
        [CardDays.clock(item.date), item.detail].compactMap { $0 }.joined(separator:" · ")
    }
}
