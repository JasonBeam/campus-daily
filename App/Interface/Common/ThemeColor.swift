import SwiftUI
import Core

/// A colour token (`Theme.ink`, `NativeTheme.tint`, …): resolved where it is drawn from the theme
/// in the view's environment (`\.appTheme`, set by `CampusRootView` from the injected
/// `ThemeStore`), so a switch redraws both page trees and nothing global holds the theme. A
/// shape style wherever a `Color` was one, and a view (a fill of its frame) wherever a `Color`
/// was drawn as one. Code that needs a plain `Color` asks `color(_:)` with the environment's theme.
struct ThemeColor: ShapeStyle {
    enum Token: Sendable {
        case bg, group, ink, ink2, ink3, separator, fill
        case accent, accentLarge, accentText, accentInk
        case redLarge, redText, pill, pillInk, notice
        /// Line icons: ink2 in 暖橙, accentText in 清爽.
        case icon
        /// Problems on the system-style pages: the system orange in 暖橙, `notice` in 清爽.
        case nativeNotice
        /// A colour that is the same in both themes, beside tokens in one expression.
        case fixed(Color)
    }

    let token: Token
    var opacity: Double = 1

    init(_ token: Token, opacity: Double = 1) {
        self.token = token; self.opacity = opacity
    }

    static func fixed(_ color: Color) -> ThemeColor { ThemeColor(.fixed(color)) }

    func resolve(in environment: EnvironmentValues) -> Color { color(environment.appTheme) }

    func color(_ theme: AppTheme) -> Color {
        let palette = ThemePalette.of(theme)
        let base: Color = switch token {
        case .bg: palette.bg
        case .group: palette.group
        case .ink: palette.ink
        case .ink2: palette.ink2
        case .ink3: palette.ink3
        case .separator: palette.separator
        case .fill: palette.fill
        case .accent: palette.accent
        case .accentLarge: palette.accentLarge
        case .accentText: palette.accentText
        case .accentInk: palette.accentInk
        case .redLarge: palette.redLarge
        case .redText: palette.redText
        case .pill: palette.pill
        case .pillInk: palette.pillInk
        case .notice: palette.notice
        case .icon: theme == .clear ? palette.accentText : palette.ink2
        case .nativeNotice: theme == .clear ? palette.notice : .orange
        case .fixed(let color): color
        }
        return opacity == 1 ? base : base.opacity(opacity)
    }

    /// The token at `value` opacity, as `Color.opacity`.
    func opacity(_ value: Double) -> ThemeColor { ThemeColor(token, opacity:opacity * value) }
}

// In an extension, so the main actor of `View` stays on `body` and the token itself can be used
// anywhere (`ShapeStyle` is resolved off the main actor).
extension ThemeColor: View {
    var body: some View { Rectangle().fill(self) }
}
