import SwiftUI

/// 「快捷指令 ›」 (opens the Shortcuts app) and how to find 校日常's actions there. 高级 shows it
/// without a header; 清爽's 设置 tab under 「快捷指令」.
struct ShortcutsSection: View {
    var header: String? = nil

    var body: some View {
        if let header {
            Section { row } header: { Text(header) } footer: { footer }.listRowBackground(Theme.group)
        } else {
            Section { row } footer: { footer }.listRowBackground(Theme.group)
        }
    }

    private var row: some View {
        Link(destination:URL(string:"shortcuts://")!) { ChevronRow(title:"快捷指令") }
    }

    private var footer: some View {
        Text("在「快捷指令」App 里搜「校日常」，就能把「开始洗澡」和「结束并结算」加到主屏幕或操作按钮上。")
    }
}
