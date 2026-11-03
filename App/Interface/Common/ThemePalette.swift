import SwiftUI
import Core

/// The colour tokens of one theme. 暖橙 reads the asset catalog (Assets.xcassets/Theme, Any/Dark),
/// 清爽 the shared `ClearPalette`; red is the same in both.
struct ThemePalette: Sendable {
    let bg, group, ink, ink2, ink3, separator, fill: Color
    let accent, accentLarge, accentText, accentInk: Color
    let redLarge, redText, pill, pillInk: Color
    let notice: Color

    static let warm = ThemePalette(
        bg:Color("Theme/bg"), group:Color("Theme/group"), ink:Color("Theme/ink"), ink2:Color("Theme/ink2"),
        ink3:Color("Theme/ink3"), separator:Color("Theme/separator"), fill:Color("Theme/fill"),
        accent:Color("Theme/accent"), accentLarge:Color("Theme/accentLarge"), accentText:Color("Theme/accentText"),
        accentInk:Color("Theme/accentInk"), redLarge:Color("Theme/redLarge"), redText:Color("Theme/redText"),
        pill:Color("Theme/pill"), pillInk:Color("Theme/pillInk"),
        // 暖橙 has no colour of its own for problems: they stay in accentText.
        notice:Color("Theme/accentText"))

    static let clear = ThemePalette(
        bg:ClearPalette.bg, group:ClearPalette.group, ink:ClearPalette.ink, ink2:ClearPalette.ink2,
        ink3:ClearPalette.ink3, separator:ClearPalette.separator, fill:ClearPalette.fill,
        accent:ClearPalette.accent, accentLarge:ClearPalette.accentLarge, accentText:ClearPalette.accentText,
        accentInk:ClearPalette.accentInk, redLarge:Color("Theme/redLarge"), redText:Color("Theme/redText"),
        pill:ClearPalette.pill, pillInk:ClearPalette.pillInk, notice:ClearPalette.notice)

    static func of(_ theme: AppTheme) -> ThemePalette { theme == .clear ? .clear : .warm }
}
