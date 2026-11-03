import SwiftUI

/// The checklist's and its step pages' primary button (his `WaterButtonStyle(primary)`): blue
/// fill with 12 pt corners, white 17 semibold, text leading and a symbol trailing, 52 pt; a spinner instead of
/// the symbol while busy.
struct ClearSetupButton: View {
    let title: String
    var symbol: String? = "arrow.right"
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action:action) {
            HStack(spacing:10) {
                Text(title).multilineTextAlignment(.leading)
                Spacer(minLength:8)
                if busy {
                    ProgressView().tint(Theme.pillInk)
                } else if let symbol {
                    Image(systemName:symbol).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(Style())
        .accessibilityLabel(title)
    }

    private struct Style: ButtonStyle {
        @Environment(\.isEnabled) private var enabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.pillInk)
                .padding(.horizontal,18).padding(.vertical,8)
                .frame(maxWidth:.infinity, minHeight:52)
                .background(Theme.pill, in:RoundedRectangle(cornerRadius:12, style:.continuous))
                .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
                .contentShape(RoundedRectangle(cornerRadius:12, style:.continuous))
        }
    }
}
