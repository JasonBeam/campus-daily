import SwiftUI
import Core

/// The widget's colours, which has no asset catalog: 暖橙 is its own apricot face (the app's accent,
/// accentText and red, warmer greys), 清爽 is `ClearPalette`. Red is the same in both.
struct CampusWidgetPalette: Sendable {
    let group, ink, ink2, ink3, separator, accent, accentText, redLarge: Color
    /// The electricity bar's track, and its track when the electricity is low.
    let track, lowTrack: Color
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
    /// `rgb` as 0xRRGGBB.
    private static func hex(_ light: UInt32, _ lightAlpha: CGFloat = 1, dark: UInt32, _ darkAlpha: CGFloat = 1) -> Color {
        func part(_ rgb: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((rgb >> shift) & 0xFF) / 255 }
        return dynamic((part(light, 16), part(light, 8), part(light, 0), lightAlpha),
                       (part(dark, 16), part(dark, 8), part(dark, 0), darkAlpha))
    }
    private static let warmAccent = hex(0xF2600B, dark:0xFF7A2E)
    private static let warmAccentText = hex(0xC2470A, dark:0xFF8A45)
    private static let red = hex(0xE5332A, dark:0xFF453A)

    /// The apricot face: ink2 5.5 / 5.6:1 and accentText 4.6 / 7.5:1 on `group`; red is for
    /// large numbers only (4.0 / 5.1:1).
    static let warm = CampusWidgetPalette(
        group:hex(0xFFF4EB, dark:0x211812),
        ink:hex(0x111111, dark:0xF5F5F5),
        ink2:hex(0x6B625C, dark:0x9A918A),
        ink3:hex(0xA39A93, dark:0x5E554F),
        separator:hex(0x6B625C, 0.18, dark:0xFFFFFF, 0.10),
        accent:warmAccent, accentText:warmAccentText, redLarge:red,
        track:hex(0xF2600B, 0.16, dark:0xFF7A2E, 0.22),
        lowTrack:hex(0xE5332A, 0.16, dark:0xFF453A, 0.16),
        notice:warmAccentText, icon:warmAccent, numberDesign:.rounded)

    static let clear = CampusWidgetPalette(
        group:ClearPalette.group, ink:ClearPalette.ink, ink2:ClearPalette.ink2, ink3:ClearPalette.ink3,
        separator:ClearPalette.separator, accent:ClearPalette.accent, accentText:ClearPalette.accentText,
        redLarge:red, track:ClearPalette.accent.opacity(0.16), lowTrack:red.opacity(0.16),
        notice:ClearPalette.notice, icon:ClearPalette.accentText, numberDesign:.default)

    static func of(_ theme: AppTheme) -> CampusWidgetPalette { theme == .clear ? .clear : .warm }
}
