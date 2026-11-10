import SwiftUI
import Core

/// 「继续设置」 on home while the account, the dorm or the usual washer is not set: opens the
/// first-run checklist.
struct ClearSetupCard: View {
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image(systemName:"slider.horizontal.3").foregroundStyle(Theme.accentText).accessibilityHidden(true)
                VStack(alignment:.leading, spacing:5) {
                    Text(HomeSetupCard.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(detail).font(.caption).foregroundStyle(Theme.ink2)
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
        .accessibilityLabel(HomeSetupCard.title + "，" + detail)
        .accessibilityIdentifier("clearSetupCard")
    }
}
