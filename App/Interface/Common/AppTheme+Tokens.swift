import SwiftUI
import Core

/// The tokens that aren't colours, for views that read the theme from `\.appTheme`.
extension AppTheme {
    /// Corner radius of a custom `group` container (sign-in form, result panel): its 暖橙 value,
    /// 16 in 清爽.
    func cardRadius(_ warm: CGFloat) -> CGFloat { self == .clear ? 16 : warm }
    var buttonShape: ThemeButtonShape { ThemeButtonShape(rounded:self == .clear) }
    /// Big numbers: rounded in 暖橙, the default design in 清爽 (monospaced digits in both).
    var numberDesign: Font.Design { self == .clear ? .default : .rounded }
    /// Home's 校园卡 and 电量 numbers.
    var heroSize: CGFloat { self == .clear ? 34 : 40 }
    var titleFont: ThemeTitleFont { self == .clear ? .clear : .warm }
}
