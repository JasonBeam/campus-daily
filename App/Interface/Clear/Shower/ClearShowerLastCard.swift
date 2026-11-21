//
//  ClearShowerLastCard.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI
import Core

/// 2.4, 最近一次用水: the last settled shower: 已结算, when it was settled (if kept), and the
/// amount, written as home's 「最近」 (「昨天 18:43」) and with 「¥」 whatever the phone's region.
struct ClearShowerLastCard: View {
    let last: ShowerLastUse
    /// The days 「今天」/「昨天」 count in, as home's 「最近」.
    @Environment(\.schoolCalendar) private var calendar

    var body: some View {
        VStack(alignment:.leading, spacing:14) {
            Text(ClearShowerText.lastUse).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment:.firstTextBaseline) {
                VStack(alignment:.leading, spacing:6) {
                    Text(ClearShowerText.lastUseSettled).font(.subheadline)
                    if let ended = last.endedText(now:Date(), calendar:calendar) {
                        Text(ended).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength:8)
                if let cost = last.cost { Text(ClearBalanceText.currency(cost)).font(.subheadline).monospacedDigit() }
            }
            .accessibilityElement(children:.combine)
        }
        .padding(18)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(NativeTheme.surface, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }
}
