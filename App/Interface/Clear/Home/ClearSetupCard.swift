import SwiftUI
import Core

/// 「继续设置」 on home while the account, the dorm or the usual washer is not set: opens the
/// first-run checklist. On a short screen where nothing else is left to give
/// (`HomeCompaction.setupTitleOnly`) the title alone, without the small line.
struct ClearSetupCard: View {
    let detail: String
    var titleOnly = false
    let action: () -> Void

    var body: some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image(systemName:"slider.horizontal.3").foregroundStyle(Theme.accentText).accessibilityHidden(true)
                VStack(alignment:.leading, spacing:5) {
                    Text(HomeSetupCard.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    if !titleOnly { Text(detail).font(.caption).foregroundStyle(Theme.ink2) }
                }
                Spacer(minLength:8)
                Image(systemName:"chevron.right").font(.caption).foregroundStyle(Theme.ink2).accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth:.infinity, alignment:.leading)
            .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
            .contentShape(RoundedRectangle(cornerRadius:16, style:.continuous))
        }
        .buttonStyle(RowPressStyle())
        // The whole sentence, with or without the small line on screen.
        .accessibilityLabel(HomeSetupCard.title + "，" + detail)
        .accessibilityIdentifier("clearSetupCard")
    }
}
