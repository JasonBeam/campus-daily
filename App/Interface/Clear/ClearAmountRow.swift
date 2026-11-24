//
//  ClearAmountRow.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI

/// 清爽's title-and-amount row. At normal text sizes the amount sits at the trailing edge beside
/// the title; at accessibility sizes it goes on its own line under the title, which then takes
/// the full width (as the laundry order card's amount does). Either way the amount stays on one
/// line, shrinking to half before it would wrap. Reading order is title, then amount.
struct ClearAmountRow<Title: View, Amount: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder let title: Title
    @ViewBuilder let amount: Amount
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment:.leading, spacing:6) {
                title
                single
            }
            .frame(maxWidth:.infinity, alignment:.leading)
        } else {
            HStack(alignment:alignment) {
                title
                Spacer(minLength:8)
                single.layoutPriority(1)
            }
        }
    }

    private var single: some View { amount.lineLimit(1).minimumScaleFactor(0.5) }
}
