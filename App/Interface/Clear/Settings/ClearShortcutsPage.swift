import SwiftUI

/// 清爽's 快捷使用: how to add 校日常's actions, and a row that opens the Shortcuts app.
struct ClearShortcutsPage: View {
    var body: some View {
        List {
            Section {
                Text(SettingsLayout.shortcutsSteps).foregroundStyle(Theme.ink)
                Text(SettingsLayout.shortcutsNote).font(.footnote).foregroundStyle(Theme.ink2)
            } header: {
                Text(SettingsLayout.shortcutsHeader)
            }.listRowBackground(Theme.group)
            Section {
                Link(destination:URL(string:"shortcuts://")!) { ChevronRow(title:SettingsLayout.shortcutsOpen) }
            }.listRowBackground(Theme.group)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accentText)
        .navigationTitle(SettingsLayout.clearRow(.shortcuts).title).navigationBarTitleDisplayMode(.inline)
    }
}
