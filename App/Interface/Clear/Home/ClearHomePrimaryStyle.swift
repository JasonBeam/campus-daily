import SwiftUI

/// 清爽's primary button on home's sheets: accent fill in both modes, white 17 semibold, radius
/// 12, at least 52 high; the label is laid out by the caller (text, spacer, symbol).
struct ClearHomePrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.pillInk)
            .padding(.horizontal,18)
            .frame(maxWidth:.infinity, minHeight:52)
            .background(Theme.pill, in:RoundedRectangle(cornerRadius:12, style:.continuous))
            .contentShape(RoundedRectangle(cornerRadius:12, style:.continuous))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.76 : 1)
    }
}
