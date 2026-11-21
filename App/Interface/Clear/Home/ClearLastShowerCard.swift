//
//  ClearLastShowerCard.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/10.
//

import SwiftUI
import Core

/// 上次热水 · 已结算 on home: when the last shower was settled (「今天 11:20」, 「11月18日 08:41」), and its amount.
struct ClearLastShowerCard: View {
    let ended: Date
    let cost: Decimal?
    /// The days 「今天」/「昨天」 count in, as home's 「最近」.
    @Environment(\.schoolCalendar) private var calendar
    /// Moves on at midnight and after a clock or time-zone change (`DayChange`).
    @State private var now = Date()

    var body: some View {
        HStack(spacing:12) {
            VStack(alignment:.leading, spacing:5) {
                Text("上次热水 · 已结算").font(.subheadline).foregroundStyle(Theme.ink)
                Text(ClearBalanceText.dayTime(ended, now:now, calendar:calendar)).font(.caption).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength:8)
            if let cost {
                Text(ClearBalanceText.currency(cost)).font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(16)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
        .accessibilityElement(children:.combine)
        .onReceive(DayChange.publisher) { now = Date() }
    }
}
