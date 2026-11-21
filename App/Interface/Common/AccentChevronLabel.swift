//
//  AccentChevronLabel.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import SwiftUI

/// 暖橙's small accent text link with a chevron, as home's 「全部 ›」 draws it: medium text and a
/// semibold chevron 2 pt smaller, 3 pt apart on the text's baseline, both in `accentText`.
struct AccentChevronLabel: View {
    struct Style: Equatable {
        let size: CGFloat
        let relativeTo: Font.TextStyle
        var weight: Font.Weight = .medium
        var chevronWeight: Font.Weight = .semibold
        var spacing: CGFloat = 3
        var color: ThemeColor = Theme.accentText
        var chevronSize: CGFloat { size - 2 }
    }

    let text: String
    let style: Style

    var body: some View {
        HStack(alignment:.firstTextBaseline, spacing:style.spacing) {
            Text(text).scaledFont(style.size, style.weight, relativeTo:style.relativeTo)
            Image(systemName:"chevron.right").scaledFont(style.chevronSize, style.chevronWeight, relativeTo:style.relativeTo)
        }
        .foregroundStyle(style.color)
    }
}
