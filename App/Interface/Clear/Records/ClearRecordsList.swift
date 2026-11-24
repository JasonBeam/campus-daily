//
//  ClearRecordsList.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI
import Core

/// 订单 while signed in: the recent laundry order and showers, then the card's records by school day, newest first, read
/// back from today as the list scrolls (`CardRecordsModel`, as 暖橙's 校园卡记录). A day's
/// 「花了」 shows once the whole day is read. The app's own showers and laundry orders open
/// their page on 日常.
struct ClearRecordsList: View {
    let orders: ClearRecentOrders
    /// The app's own showers and laundry orders: merged into the school's rows, and shown alone
    /// when the school's records can't be read.
    let app: [AppActivity]
    @StateObject private var model: CardRecordsModel
    /// Rows of the kept showers' section on screen.
    @State private var retainedOnScreen = 0
    /// The recent orders' 「今天」/「昨天」 move on at midnight and after a clock change.
    @State private var clock = Date()
    @Environment(ClearNavigator.self) private var navigator
    @Environment(\.campusServices) private var campusServices
    @EnvironmentObject private var laundry: LaundryModel

    init(orders: ClearRecentOrders, app: [AppActivity], source: CardRecordsSource) {
        self.orders = orders
        self.app = app
        _model = StateObject(wrappedValue:CardRecordsModel(source:source))
    }

    var body: some View {
        let days = days(now:Date())
        ScrollViewReader { proxy in
        List {
            ClearRecentOrdersSections(orders:orders, now:clock) { retainedOnScreen = max(0, retainedOnScreen + $0) }
            // The stats say when the records are being read or could not be.
            Section {
                CardRecordsStats(model:model)
                    .listRowInsets(EdgeInsets(top:4, leading:0, bottom:8, trailing:0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text("消费统计")
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.items) { row($0) }
                } header: {
                    // Under the stats, the records start with their own heading.
                    if day.id == days.first?.id {
                        VStack(alignment:.leading, spacing:14) {
                            Text("校园卡记录").accessibilityAddTraits(.isHeader)
                            header(day)
                        }
                    } else {
                        header(day)
                    }
                }
            }
            footer(empty:days.isEmpty)
        }
        .listStyle(.insetGrouped)
        .onAppear { clock = Date() }
        .onReceive(DayChange.publisher) { clock = Date() }
        // SwiftUI cancels the pull's own task when the list changes under it (the read starting
        // does): a read cancelled that way would come back as failed. The read runs on its own.
        .refreshable { await Task { await model.reload() }.value }
        .task {
            model.bind(campusServices.defaults)
            if model.phase == .loading { await model.reload() }
        }
        // The hot-water page's kept line: its section to the top, unless it is already in view.
        .task(id:navigator.recordsScroll) {
            guard let target = navigator.recordsScroll else { return }
            try? await Task.sleep(for:.milliseconds(150))
            navigator.recordsScroll = nil
            guard target != .showerRetained || retainedOnScreen == 0 else { return }
            withAnimation { proxy.scrollTo(ClearRecentOrders.scrollID(target), anchor:.top) }
        }
        }
    }

    private func days(now: Date) -> [CardDay] {
        switch model.phase {
        case .loading: return []
        case .failed: return CardDays.groups(history:nil, app:app, now:now, calendar:model.calendar)
        case .loaded: return model.history.map { CardDays.groups(history:$0, app:app, now:now, calendar:model.calendar) } ?? []
        }
    }

    // MARK: Days

    private func header(_ day: CardDay) -> some View {
        HStack(alignment:.firstTextBaseline) {
            Text(day.title)
            Spacer(minLength:12)
            if let total = day.totalText { Text(total).monospacedDigit() }
        }
        .textCase(nil)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(day.spokenTitle)
        .accessibilityAddTraits(.isHeader)
    }

    /// The app's own showers and open orders open their page on 日常; finished orders and card records are plain rows.
    @ViewBuilder private func row(_ item: RecentItem) -> some View {
        if item.source == .app, item.opensPage {
            Button {
                navigator.openOnHome(item.kind == .laundry ? .laundry : .shower, laundry:laundry.checkout?.phase, from:.cardRecords)
            } label: {
                ClearLinkRow { ClearRecordRow(item:item) }
            }
        } else {
            ClearRecordRow(item:item)
        }
    }

    // MARK: States

    @ViewBuilder private func footer(empty: Bool) -> some View {
        if model.phase == .loaded, let history = model.history {
            if model.loadingMore {
                ProgressView().frame(maxWidth:.infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("正在读更早的记录")
            } else if model.moreFailed {
                Section {
                    Button { Task { await model.loadMore() } } label: {
                        Label("没读到更早的记录，点这里再试", systemImage:"arrow.clockwise")
                            .foregroundStyle(Theme.accentText)
                    }
                    .accessibilityIdentifier("recordsRetryMore")
                }
            } else if history.reachedEnd {
                if empty { emptyRow } else {
                    Text("没有更早的记录了").font(.footnote).foregroundStyle(Color.secondary)
                        .frame(maxWidth:.infinity)
                        .listRowBackground(Color.clear)
                }
            } else {
                // The end of the list came into view: read further back. A new one with each
                // pull that comes in, as one already in view does not appear again.
                Color.clear.frame(height:44)
                    .listRowBackground(Color.clear)
                    .onAppear { Task { await model.loadMore() } }
                    .id(model.reloads)
            }
        }
    }

    private var emptyRow: some View {
        ContentUnavailableView("还没有记录", systemImage:"clock",
                               description:Text("刷了校园卡，过一会儿就会出现在这里。"))
            .listRowBackground(Color.clear)
    }
}
