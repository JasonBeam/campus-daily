import SwiftUI
import Core

/// The widget's colours, which has no asset catalog: 暖橙 repeats App/Resources/Assets.xcassets/Theme,
/// 清爽 is `ClearPalette`. Red is the same in both.
struct CampusWidgetPalette: Sendable {
    let group, ink, ink2, ink3, separator, accent, accentText, redLarge: Color
    /// 「登录过期了」.
    let notice: Color
    /// creditcard and bolt.
    let icon: Color
    /// The two numbers: rounded in 暖橙.
    let numberDesign: Font.Design

    private static func dynamic(_ light: (CGFloat, CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red:c.0, green:c.1, blue:c.2, alpha:c.3)
        })
    }
    private static let warmInk2 = dynamic((0.431, 0.431, 0.431, 1), (0.549, 0.549, 0.549, 1))
    private static let warmAccentText = dynamic((0.761, 0.278, 0.039, 1), (1, 0.541, 0.271, 1))
    private static let red = dynamic((0.898, 0.200, 0.165, 1), (1, 0.271, 0.227, 1))

    static let warm = CampusWidgetPalette(
        group:dynamic((1, 1, 1, 1), (0.110, 0.110, 0.118, 1)),
        ink:dynamic((0.067, 0.067, 0.067, 1), (0.961, 0.961, 0.961, 1)),
        ink2:warmInk2,
        ink3:dynamic((0.769, 0.769, 0.769, 1), (0.290, 0.290, 0.290, 1)),
        separator:dynamic((0, 0, 0, 0.08), (1, 1, 1, 0.09)),
        accent:dynamic((0.949, 0.376, 0.047, 1), (1, 0.478, 0.180, 1)),
        accentText:warmAccentText, redLarge:red, notice:warmAccentText, icon:warmInk2, numberDesign:.rounded)

    static let clear = CampusWidgetPalette(
        group:ClearPalette.group, ink:ClearPalette.ink, ink2:ClearPalette.ink2, ink3:ClearPalette.ink3,
        separator:ClearPalette.separator, accent:ClearPalette.accent, accentText:ClearPalette.accentText,
        redLarge:red, notice:ClearPalette.notice, icon:ClearPalette.accentText, numberDesign:.default)

    static func of(_ theme: AppTheme) -> CampusWidgetPalette { theme == .clear ? .clear : .warm }
}
