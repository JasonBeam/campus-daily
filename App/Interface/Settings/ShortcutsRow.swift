//
//  ShortcutsRow.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/10.
//

import SwiftUI

/// 「快捷指令 ›」: opens the Shortcuts app.
struct ShortcutsRow: View {
    var body: some View {
        Link(destination:URL(string:"shortcuts://")!) { ChevronRow(title:"快捷指令") }
    }
}
