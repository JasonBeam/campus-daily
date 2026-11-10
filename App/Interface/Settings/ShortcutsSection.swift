import SwiftUI

/// 「快捷指令 ›」 (opens the Shortcuts app) and how to find 校日常's actions there, as 高级 shows it.
struct ShortcutsSection: View {
    var body: some View {
        Section { ShortcutsRow() } footer: { ShortcutsFooter() }.listRowBackground(Theme.group)
    }
}
