import SwiftUI

/// The 清爽 colours (light / dark), one copy for the app's `Theme`, the widget and the Live
/// Activities. The system grouped-list values with one blue tint; red stays the 暖橙 red.
enum ClearPalette {
    /// `rgb` as 0xRRGGBB.
    private static func dynamic(_ light: UInt32, _ lightAlpha: Double = 1, dark: UInt32, _ darkAlpha: Double = 1) -> Color {
        Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let rgb = isDark ? dark : light
            return UIColor(red:CGFloat((rgb >> 16) & 0xFF) / 255, green:CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue:CGFloat(rgb & 0xFF) / 255, alpha:isDark ? darkAlpha : lightAlpha)
        })
    }

    static let bg = dynamic(0xF2F2F7, dark:0x000000)
    static let group = dynamic(0xFFFFFF, dark:0x1C1C1E)
    static let ink = dynamic(0x000000, dark:0xFFFFFF)
    static let ink2 = dynamic(0x3C3C43, 0.6, dark:0xEBEBF5, 0.6)
    static let ink3 = dynamic(0x3C3C43, 0.3, dark:0xEBEBF5, 0.3)
    static let separator = dynamic(0x3C3C43, 0.29, dark:0x545458, 0.65)
    static let fill = dynamic(0x175EC9, 0.10, dark:0x8ABAFF, 0.14)
    static let accent = dynamic(0x175EC9, dark:0x175EC9)
    static let accentLarge = dynamic(0x175EC9, dark:0x8ABAFF)
    static let accentText = dynamic(0x175EC9, dark:0x8ABAFF)
    static let accentInk = dynamic(0xFFFFFF, dark:0xFFFFFF)
    static let pill = dynamic(0x175EC9, dark:0x175EC9)
    static let pillInk = dynamic(0xFFFFFF, dark:0xFFFFFF)
    /// Errors, 「暂停」 and the school's refusals: orange, so they don't read as links.
    static let notice = dynamic(0xB25000, dark:0xFF9F0A)
    /// The Live Activities' accent on their dark card.
    static let liveAccent = Color(red:0x8A / 255, green:0xBA / 255, blue:1)
}
