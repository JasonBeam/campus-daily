import SwiftUI

/// The primary button's row: text, then a trailing symbol or a spinner while busy.
struct ClearLaundryButtonLabel: View {
    let title: String
    var symbol: String?
    var busy = false
    var minHeight: CGFloat = 52

    var body: some View {
        HStack(spacing:10) {
            Text(title).monospacedDigit().multilineTextAlignment(.leading)
            Spacer(minLength:8)
            if busy {
                ProgressView().tint(Theme.accentInk)
            } else if let symbol {
                Image(systemName:symbol).accessibilityHidden(true)
            }
        }
        .padding(.horizontal,18).padding(.vertical,8)
        .frame(maxWidth:.infinity, minHeight:minHeight)
        .contentShape(Rectangle())
    }
}
