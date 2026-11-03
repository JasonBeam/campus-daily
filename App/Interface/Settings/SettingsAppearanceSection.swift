import SwiftUI
import Core

/// 外观 › 主题.
struct SettingsAppearanceSection<Link: View>: View {
    @Environment(\.appTheme) private var appTheme
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        Section("外观") {
            link(.theme, SettingsRow(symbol:"paintpalette", title:"主题", value:appTheme.name))
                .accessibilityLabel(appTheme.settingsRowLabel)
                .accessibilityIdentifier("themeRow")
        }.listRowBackground(Theme.group)
    }
}
