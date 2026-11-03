import SwiftUI

/// Shared native appearance; the WidgetKit/Scriptable renderer has separate tokens.
enum NativeTheme {
    static let background = Color(uiColor:.systemGroupedBackground)
    static let surface = Color(uiColor:.secondarySystemGroupedBackground)
    // One accent app-wide; primary buttons use the black/white pill colors.
    static let tint = Theme.accentText
    static let action = Theme.pill
    static let radius: CGFloat = 16
}
