//
//  ClearShowerRetainedLine.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import SwiftUI
import Core

/// The kept showers on 热水洗澡: one footnote line with their count and a chevron, flush with the
/// cards above; a tap opens 订单 at their section. Read-only: nothing here settles or deletes them.
struct ClearShowerRetainedLine: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action:open) {
            HStack(spacing:8) {
                Text(ShowerRetainedText.Clear.line(count:count))
                    .font(.footnote).foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal:false, vertical:true)
                    .frame(maxWidth:.infinity, alignment:.leading)
                Image(systemName:"chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor:.tertiaryLabel))
            }
            .frame(maxWidth:.infinity, minHeight:44, alignment:.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(ShowerRetainedText.Clear.spoken(count:count))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("showerRetainedLine")
    }
}
