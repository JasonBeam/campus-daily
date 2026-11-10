import SwiftUI
import Core

/// 外观 › 主题.
struct SettingsAppearanceSection<Link: View>: View {
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        Section(SettingsLayout.appearance.title) {
            ForEach(SettingsLayout.appearance.items, id:\.self) { item in
                if item == .theme { SettingsThemeRow(link:link) }
            }
        }.listRowBackground(Theme.group)
    }
}
