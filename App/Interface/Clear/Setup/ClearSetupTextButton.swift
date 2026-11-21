//
//  ClearSetupTextButton.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI

/// A plain text button under the primary one, full width, 44 pt.
struct ClearSetupTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action:action) {
            Text(title).font(.body).foregroundStyle(Theme.accentText)
                .frame(maxWidth:.infinity, minHeight:44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
