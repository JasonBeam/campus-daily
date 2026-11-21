//
//  ClearRecentOrdersSections.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/10.
//

import SwiftUI
import Core

/// 「最近洗衣订单」, 「当前热水记录」, 「最近热水结算」 and the kept showers, each only when it has
/// a row; each row but the kept showers' opens its page on 日常 (those are plain, read-only rows).
struct ClearRecentOrdersSections: View {
    let orders: ClearRecentOrders
    /// What 「今天」/「昨天」 count from: the list's clock, moved on at midnight (`DayChange`).
    var now = Date()
    /// A row of the kept showers came on screen (+1) or went off it (-1): the list scrolls to
    /// them only when none is on screen.
    var retainedVisible: (Int) -> Void = { _ in }
    @Environment(ClearNavigator.self) private var navigator
    @EnvironmentObject private var laundry: LaundryModel
    /// The days 「今天」/「昨天」 count in, as home's.
    @Environment(\.schoolCalendar) private var calendar

    var body: some View {
        if let order = orders.laundry {
            Section(ClearRecentOrders.laundryTitle) {
                link(.laundry, id:"recordsOpenLaundry") {
                    VStack(alignment:.leading, spacing:8) {
                        Text(order.title).font(.headline).foregroundStyle(Color.primary)
                        Text(order.program).font(.subheadline).foregroundStyle(Color.secondary)
                        if let amount = order.amount { Text(ClearCNY.text(amount)).monospacedDigit().foregroundStyle(Color.primary) }
                    }
                    .padding(.vertical,6)
                }
            }
        }
        if let open = orders.showerOpen {
            Section(ClearRecentOrders.showerOpenTitle) {
                link(.shower, id:"recordsOpenShower") {
                    VStack(alignment:.leading, spacing:6) {
                        Text(open.title).font(.headline).foregroundStyle(Color.primary)
                        status(open.status).font(.subheadline)
                    }
                    .padding(.vertical,6)
                }
            }
        }
        if let settled = orders.showerSettled {
            Section(ClearRecentOrders.showerSettledTitle) {
                link(.shower, id:"recordsSettledShower") {
                    HStack {
                        VStack(alignment:.leading, spacing:6) {
                            Text(ClearRecentOrders.settled).foregroundStyle(Color.primary)
                            Text(ClearBalanceText.dayTime(settled.date, now:now, calendar:calendar))
                                .font(.caption).foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength:8)
                        if let amount = settled.amount {
                            Text(ClearCNY.text(amount)).monospacedDigit().foregroundStyle(Color.primary)
                        } else {
                            Text(ClearRecentOrders.noAmount).font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                    .padding(.vertical,6)
                }
            }
        }
        retainedSection
    }

    /// Read-only rows, two lines each (when, then 机器 · 原因; then 「校园卡已扣 ¥x」 when the card's
    /// records show the charge), newest first; each read as one sentence.
    @ViewBuilder private var retainedSection: some View {
        if orders.retained != nil {
            Section {
                ForEach(Array(orders.retainedLines(now:now).enumerated()), id:\.offset) { _, line in
                    VStack(alignment:.leading, spacing:4) {
                        Text(line.title).font(.body).foregroundStyle(Color.primary)
                        if let detail = line.detail {
                            Text(detail).font(.subheadline).foregroundStyle(Color.secondary)
                        }
                        if let charge = line.charge {
                            Text(charge).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Color.primary)
                        }
                    }
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.vertical,4)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(line.spoken)
                    .onAppear { retainedVisible(1) }
                    .onDisappear { retainedVisible(-1) }
                }
            } header: {
                Text(ClearRecentOrders.retainedTitle)
            } footer: {
                Text(ClearRecentOrders.retainedFooter)
            }
            .id(ClearRecentOrders.scrollID(.showerRetained))
            .accessibilityIdentifier("recordsRetainedShowers")
        }
    }

    /// Their pages live on 日常 (the shower page is the root's there).
    private func link(_ route: ClearRoute, id: String, @ViewBuilder label: () -> some View) -> some View {
        Button { navigator.openOnHome(route, laundry:laundry.checkout?.phase, from:.cardRecords) } label: {
            ClearLinkRow { label().fixedSize(horizontal:false, vertical:true).accessibilityElement(children:.combine) }
        }
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private func status(_ status: ClearOpenItem.Status) -> some View {
        switch status {
        case .text(let text, let notice):
            if notice { ClearNoticeText(text) } else { Text(text).foregroundStyle(Color.secondary) }
        }
    }
}
