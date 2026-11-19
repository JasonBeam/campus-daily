import SwiftUI

/// 清爽's primary button on the laundry page and its sheets: accent fill, white 17 semibold,
/// radius 12. The label brings its own height and padding (`ClearLaundryButtonLabel`).
struct ClearLaundryPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.accentInk)
            .background(Theme.accent, in:RoundedRectangle(cornerRadius:12, style:.continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
    }
}
