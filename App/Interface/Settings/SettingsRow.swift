import SwiftUI

/// Icon (`RowIcon`, 20pt in a 26pt column) · title · value in ink2.
struct SettingsRow: View {
    /// SF Symbol name; nil keeps the column empty (a sub-row aligned with the row above).
    let symbol: String?
    let title: String
    var value: String? = nil
    /// Second line under the title (a full location), 13 ink2, wraps; replaces `value`.
    var detail: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.title3) private var iconColumn: CGFloat = 26
    var body: some View {
        HStack(spacing:12) {
            Group { if let symbol { RowIcon(symbol:symbol) } else { Color.clear.frame(height:1) } }
                .frame(width:iconColumn)
            if let detail {
                VStack(alignment:.leading, spacing:2) {
                    titleText
                    Text(detail).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                        .accessibilityLabel(detail.replacingOccurrences(of:" · ", with:"，"))
                }
                .frame(minHeight:62, alignment:.leading)
                Spacer(minLength:0)
            } else if typeSize.isAccessibilitySize {
                // Large text: value goes under the title instead of being truncated.
                VStack(alignment:.leading, spacing:2) {
                    titleText
                    if let value { Text(value).foregroundStyle(Theme.ink2) }
                }
                Spacer(minLength:0)
            } else {
                titleText
                Spacer(minLength:8)
                if let value { Text(value).foregroundStyle(Theme.ink2).lineLimit(1).minimumScaleFactor(0.8) }
            }
        }
        .accessibilityElement(children:.combine)
    }
    private var titleText: some View {
        Text(title).foregroundStyle(Theme.ink)
            // Separator starts under the title, not the icon.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}
