import SwiftUI
import Core

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.standard
}

extension EnvironmentValues {
    /// The theme the pages draw with: `CampusRootView` sets it from the injected `ThemeStore`;
    /// `ThemeColor` tokens and views that pick a design, a size or a shape by theme read it.
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
