import SwiftUI

/// The 热水 page's primary button in 清爽: the blue fill and white label of his
/// `ShowerButtonStyle` while it can be tapped. Disabled (正在连接水控…, 正在结算…) it takes the
/// system's disabled look, a grey fill with the secondary label colour, which stays legible in
/// light and dark instead of a faded blue.
struct ClearShowerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(enabled ? Theme.pillInk : .fixed(Color(uiColor:.secondaryLabel)))
            .tint(enabled ? Theme.pillInk : .fixed(Color(uiColor:.secondaryLabel)))
            .background(enabled ? NativeTheme.action : .fixed(Color(uiColor:.tertiarySystemFill)), in:RoundedRectangle(cornerRadius:12))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}
