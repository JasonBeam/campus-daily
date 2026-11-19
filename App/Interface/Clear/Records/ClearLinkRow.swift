import SwiftUI

/// A list row that opens a page on another tab: drawn as a NavigationLink row (its chevron), since
/// 记录 hands the shower and laundry pages to 日常 instead of pushing them on its own stack.
struct ClearLinkRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing:8) {
            content
            Spacer(minLength:0)
            Image(systemName:"chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(uiColor:.tertiaryLabel))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
