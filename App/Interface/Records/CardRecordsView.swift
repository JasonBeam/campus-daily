import SwiftUI
import Core

/// 校园卡记录: the card's records by school day, newest first, read back from today as the list
/// scrolls. A day's 「花了」 shows once the whole day is read.
struct CardRecordsView: View {
    /// The app's own showers and laundry orders (as on home): merged into the school's rows, and
    /// shown alone when the school's records can't be read.
    let app: [AppActivity]
    @StateObject private var model: CardRecordsModel
    @Environment(\.dynamicTypeSize) private var typeSize

    init(app: [AppActivity], source: CardRecordsSource) {
        self.app = app
        _model = StateObject(wrappedValue:CardRecordsModel(source:source))
    }

    var body: some View {
        let now = Date()
        let days = days(now:now)
        ScrollView {
            LazyVStack(alignment:.leading, spacing:0, pinnedViews:[.sectionHeaders]) {
                switch model.phase {
                case .loading: loadingLine
                case .failed: failedLine
                case .loaded: EmptyView()
                }
                ForEach(Array(days.enumerated()), id:\.element.id) { index, day in
                    Section {
                        rows(day)
                    } header: {
                        header(day, first:index == 0 && model.phase == .loaded)
                    }
                }
                footer(empty:days.isEmpty)
            }
            .padding(.top,8).padding(.bottom,40)
            .frame(maxWidth:600)
            .frame(maxWidth:.infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("校园卡记录")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: Day groups

    private func header(_ day: CardDay, first: Bool) -> some View {
        ViewThatFits(in:.horizontal) {
            HStack(alignment:.firstTextBaseline) {
                dayTitle(day)
                Spacer(minLength:12)
                dayTotal(day)
            }
            VStack(alignment:.leading, spacing:2) {
                dayTitle(day)
                dayTotal(day)
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .padding(.horizontal,24).padding(.top,first ? 8 : 22).padding(.bottom,6)
        .background(Theme.bg)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(day.spokenTitle)
        .accessibilityAddTraits(.isHeader)
    }

    private func dayTitle(_ day: CardDay) -> some View {
        Text(day.title).scaledFont(13, .semibold, relativeTo:.footnote).foregroundStyle(Theme.ink2)
            .fixedSize(horizontal:false, vertical:true)
    }

    @ViewBuilder private func dayTotal(_ day: CardDay) -> some View {
        if let total = day.totalText {
            Text(total).scaledFont(13, .medium, relativeTo:.footnote).monospacedDigit().foregroundStyle(Theme.ink2)
        }
    }

    /// The app's own showers and orders open their page; card records are plain rows.
    private func rows(_ day: CardDay) -> some View {
        VStack(spacing:0) {
            ForEach(Array(day.items.enumerated()), id:\.element.id) { index, item in
                if index > 0 { RowSeparator() }
                if item.source == .app {
                    NavigationLink(value:item.kind == .laundry ? HomeRoute.laundry : HomeRoute.shower) {
                        RecentRow(item:item, clockOnly:true)
                    }
                    .buttonStyle(RowPressStyle())
                } else {
                    RecentRow(item:item, clockOnly:true)
                }
            }
        }
    }

    // MARK: States

    private var loadingLine: some View {
        HStack(spacing:6) {
            ProgressView().controlSize(.mini).frame(width:12, height:12).accessibilityHidden(true)
            Text("正在读记录…")
        }
        .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
        .accessibilityElement(children:.combine)
        .padding(.horizontal,24).padding(.top,16)
        .accessibilityIdentifier("recordsLoading")
    }

    private var failedLine: some View {
        HStack(alignment:.firstTextBaseline, spacing:5) {
            Image(systemName:"exclamationmark.circle.fill").accessibilityHidden(true)
            Text("没读到记录，下拉再试。").fixedSize(horizontal:false, vertical:true)
        }
        .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.accentText)
        .accessibilityElement(children:.combine)
        .padding(.horizontal,24).padding(.top,16)
        .accessibilityIdentifier("recordsFailed")
    }

    @ViewBuilder private func footer(empty: Bool) -> some View {
        if model.phase == .loaded, let history = model.history {
            if model.loadingMore {
                ProgressView().controlSize(.small).frame(maxWidth:.infinity).frame(height:56)
                    .accessibilityLabel("正在读更早的记录")
            } else if model.moreFailed {
                Button { Task { await model.loadMore() } } label: {
                    HStack(spacing:6) {
                        Image(systemName:"arrow.clockwise").scaledFont(13, relativeTo:.footnote)
                        Text("没读到更早的记录，点这里再试").scaledFont(13, .medium, relativeTo:.footnote)
                    }
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth:.infinity).frame(minHeight:56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("recordsRetryMore")
            } else if history.reachedEnd {
                if empty { emptyBlock } else {
                    Text("没有更早的记录了").scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                        .frame(maxWidth:.infinity).frame(minHeight:56)
                }
            } else {
                // The end of the list came into view: read further back. A new one with each
                // pull that comes in, as one already in view does not appear again.
                Color.clear.frame(height:56)
                    .onAppear { Task { await model.loadMore() } }
                    .id(model.reloads)
            }
        }
    }

    private var emptyBlock: some View {
        VStack(spacing:0) {
            Mascot(size:64, hops:false)
            Text("还没有记录").scaledFont(17, .semibold, relativeTo:.headline).foregroundStyle(Theme.ink)
                .padding(.top,14)
            Text("刷了校园卡，过一会儿就会出现在这里。").scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).frame(maxWidth:280)
                .fixedSize(horizontal:false, vertical:true)
                .padding(.top,6)
        }
        .frame(maxWidth:.infinity)
        .padding(.top,112).padding(.horizontal,24)
        .accessibilityElement(children:.combine)
    }
}
