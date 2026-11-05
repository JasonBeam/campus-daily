import SwiftUI
import Core

/// 记录 while signed in: 「进行中」, then the card's records by school day, newest first, read
/// back from today as the list scrolls (`CardRecordsModel`, as 暖橙's 校园卡记录). A day's
/// 「花了」 shows once the whole day is read. The app's own showers and laundry orders open
/// their page on 日常.
struct ClearRecordsList: View {
    let open: [ClearOpenItem]
    /// The app's own showers and laundry orders: merged into the school's rows, and shown alone
    /// when the school's records can't be read.
    let app: [AppActivity]
    @StateObject private var model: CardRecordsModel
    @Environment(ClearNavigator.self) private var navigator
    @EnvironmentObject private var laundry: LaundryModel

    init(open: [ClearOpenItem], app: [AppActivity], source: CardRecordsSource) {
        self.open = open
        self.app = app
        _model = StateObject(wrappedValue:CardRecordsModel(source:source))
    }

    var body: some View {
        let days = days(now:Date())
        List {
            ClearOpenSection(items:open)
            switch model.phase {
            case .loading: loadingSection
            case .failed: failedSection
            case .loaded: EmptyView()
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.items) { row($0) }
                } header: {
                    header(day)
                }
            }
            footer(empty:days.isEmpty)
        }
        .listStyle(.insetGrouped)
        // SwiftUI cancels the pull's own task when the list changes under it (the read starting
        // does): a read cancelled that way would come back as failed. The read runs on its own.
        .refreshable { await Task { await model.reload() }.value }
        .task { if model.phase == .loading { await model.reload() } }
    }

    private func days(now: Date) -> [CardDay] {
        switch model.phase {
        case .loading: return []
        case .failed: return CardDays.groups(history:nil, app:app, now:now)
        case .loaded: return model.history.map { CardDays.groups(history:$0, app:app, now:now) } ?? []
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

    /// The app's own showers and orders open their page on 日常; card records are plain rows.
    @ViewBuilder private func row(_ item: RecentItem) -> some View {
        if item.source == .app {
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

    private var loadingSection: some View {
        Section {
            HStack(spacing:10) {
                ProgressView().accessibilityHidden(true)
                Text("正在读记录…").foregroundStyle(Color.secondary)
            }
            .accessibilityElement(children:.combine)
            .accessibilityIdentifier("recordsLoading")
        }
    }

    private var failedSection: some View {
        Section {
            Label("没读到记录，下拉再试。", systemImage:"exclamationmark.circle.fill")
                .font(.footnote).foregroundStyle(Theme.notice)
                .accessibilityIdentifier("recordsFailed")
        }
    }

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
