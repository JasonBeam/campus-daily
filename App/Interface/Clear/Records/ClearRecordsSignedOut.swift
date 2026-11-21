//
//  ClearRecordsSignedOut.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI

/// 订单 while signed out: 「登录后显示」 with 「登录学校账号」, which opens the first-run checklist
/// at 学校账号; under the recent orders when there are some.
struct ClearRecordsSignedOut: View {
    let orders: ClearRecentOrders
    @Environment(ClearNavigator.self) private var navigator
    /// The rows' 「今天」/「昨天」 move on at midnight and after a clock change.
    @State private var clock = Date()

    var body: some View {
        if orders.sections.isEmpty {
            signIn
                .frame(maxWidth:.infinity, maxHeight:.infinity)
                .background(Color(uiColor:.systemGroupedBackground))
        } else {
            List {
                ClearRecentOrdersSections(orders:orders, now:clock)
                signIn.listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .onAppear { clock = Date() }
            .onReceive(DayChange.publisher) { clock = Date() }
        }
    }

    private var signIn: some View {
        ContentUnavailableView {
            Label("登录后显示", systemImage:"person.crop.circle")
        } actions: {
            Button { navigator.openSetup(at:.account, from:.cardRecords) } label: {
                Text("登录学校账号").font(.headline).padding(.horizontal,8).frame(minHeight:40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius:12))
            .tint(Theme.accent)
            .padding(.top,8)
            .accessibilityIdentifier("recordsSignIn")
        }
    }
}
