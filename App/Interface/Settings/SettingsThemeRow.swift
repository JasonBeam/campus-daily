import SwiftUI
import Core

/// 主题, with the current theme's name.
struct SettingsThemeRow<Link: View>: View {
    @Environment(\.appTheme) private var appTheme
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        link(.theme, SettingsRow(symbol:"paintpalette", title:"主题", value:appTheme.name))
            .accessibilityLabel(appTheme.settingsRowLabel)
            .accessibilityIdentifier("themeRow")
    }
}
