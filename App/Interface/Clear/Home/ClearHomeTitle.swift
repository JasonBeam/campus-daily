import SwiftUI

/// 「校日常」 as a large title over home's page, under an inline bar that shows no title: drawn
/// by home rather than the bar, so it can give way to the bar's small title on a short screen
/// (`HomeCompaction.inlineTitle`) and come back, which the bar's own large title does not do.
/// Placed where the bar's large title sits on the other tabs.
struct ClearHomeTitle: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Text("校日常")
            .font(.largeTitle.bold())
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            // The bar's large-title area: 52 high, the text 16 in and one pixel less than 8 over its
            // bottom, at every text size below the accessibility ones (the bar's title hardly
            // grows). At the default size this draws the same pixels as the bar's own large title
            // on 记录 (iPhone SE and 18 Pro).
            .padding(.horizontal,16).padding(.bottom,8 - 1 / displayScale)
            .frame(maxWidth:.infinity, minHeight:52, maxHeight:52, alignment:.bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }
}
