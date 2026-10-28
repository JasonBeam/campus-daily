import SwiftUI

/// Shared native appearance; the WidgetKit/Scriptable renderer has separate tokens.
enum NativeTheme {
    static let background = Color(uiColor:.systemGroupedBackground)
    static let surface = Color(uiColor:.secondarySystemGroupedBackground)
    static let tint = Color(uiColor:UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.54,green:0.73,blue:1,alpha:1) : UIColor(red:0.09,green:0.37,blue:0.79,alpha:1)
    })
    static let action = Color(red:0.09,green:0.37,blue:0.79)
    static let radius: CGFloat = 16
}

// Keep existing auxiliary screens on the same palette without changing their flows.
enum NothingTheme {
    static let background = NativeTheme.background
    static let surface = NativeTheme.surface
    static let ink = NativeTheme.tint
    static let signal = Color.orange
    static func label(_ size: CGFloat = 12) -> Font { .system(size:size,weight:.regular) }
    static func display(_ size: CGFloat = 34) -> Font { .system(size:size,weight:.semibold,design:.rounded) }
}

struct NothingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).foregroundStyle(.white)
            .frame(maxWidth:.infinity,minHeight:52)
            .background(NativeTheme.action,in:RoundedRectangle(cornerRadius:12))
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
    }
}
