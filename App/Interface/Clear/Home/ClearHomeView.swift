import SwiftUI
import Core

/// 日常 tab root (清爽 home): room line, 电量和校园卡, 继续设置 while something is not set,
/// the 热水 and 洗衣 tiles, and as many 最近 rows as fit (`RecentCardFit`), so home never scrolls
/// below the accessibility sizes. On a short screen it first compresses (`HomeCompaction`): no
/// room line, then the inline title, then tighter cards, then 继续设置 without its small line.
///
/// Pages open through `ClearNavigator`; the root hosts the shower page, the laundry-done sheet
/// and the sign-in sheet.
struct ClearHomeView: View {
    @EnvironmentObject var shower: ShowerModel
    @EnvironmentObject var campus: CampusModel
    @EnvironmentObject var laundry: LaundryModel
    @Environment(ClearNavigator.self) var navigator
    @Environment(SampleMode.self) var sample
    @Environment(\.appTheme) var appTheme
    @Environment(\.dynamicTypeSize) var typeSize
    /// The dorm confirmed on the checklist (a dorm may have no controller to bind).
    @AppStorage(SetupChecklist.dormKey) var confirmedDorm = ""
    /// For 最近 (`recentCount`): the scroll view's visible size, the tiles' bottom, the header's
    /// height and each row's height, measured hidden at the card's width.
    @State var viewport: CGSize = .zero
    @State var tilesBottom: CGFloat = 0
    @State var recentsHeaderHeight: CGFloat = 0
    @State var recentHeights: [RecentItem.ID: CGFloat] = [:]
    /// For `compaction`: the title and the sections measured hidden, as designed and tightened,
    /// at `sectionsWidth`.
    @State var sections = HomeCompaction.Sections(title:0, roomLine:0, balance:0, balanceTight:0, setup:0, setupShort:0, tiles:0,
                                                   tilesTight:0)
    @State var sectionsWidth: CGFloat = 0

    static let fit = RecentCardFit.clearHome
    nonisolated static let contentSpace = "clearHomeContent"

    var body: some View {
        let data = navigator.data(campus:campus, shower:shower, laundry:laundry)
        let step = compaction
        // Not `.scrollBounceBehavior(.basedOnSize)`: content that fits must still bounce for the pull.
        ScrollView {
            content(data, step:step)
        }
        // The size between the bars: what the page and 最近 have to fit in.
        .onGeometryChange(for:CGSize.self) { $0.size } action: { viewport = $0 }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("校日常")
        // At accessibility sizes the page scrolls: the bar's own large title, which shrinks into
        // the bar. Otherwise the bar is inline and home draws the large title (`ClearHomeTitle`)
        // until a short screen needs the bar's small one.
        .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .large : .inline)
        .toolbar {
            if !typeSize.isAccessibilitySize {
                ToolbarItem(placement:.principal) {
                    Text("校日常").font(.headline).foregroundStyle(Theme.ink.color(appTheme))
                        .opacity(step.usesInlineTitle ? 1 : 0)
                        .accessibilityHidden(!step.usesInlineTitle)
                }
            }
        }
        // SwiftUI may cancel the pull's own task when the page changes under it: the read runs
        // on its own and the pull waits for it.
        .refreshable { await Task { await pull() }.value }
    }

    func content(_ data: HomeData, step: HomeCompaction) -> some View {
        let fit = Self.fit
        return VStack(spacing:0) {
            if showsLargeTitle(step) { ClearHomeTitle() }
            VStack(alignment:.leading, spacing:CGFloat(fit.gapAbove)) {
                if !step.hidesRoomLine { roomLine(data) }
                ClearBalanceCard(data:data, tight:step.tightensCards)
                setupCard(data, titleOnly:step.shortensSetup)
                tiles(data, tight:step.tightensCards)
                    .onGeometryChange(for:CGFloat.self) { $0.frame(in:.named(Self.contentSpace)).maxY } action: { tilesBottom = $0 }
                recents(data)
            }
            .padding(CGFloat(fit.pagePadding))
            .background(alignment:.top) { recentMeasure(data) }
            .background(alignment:.top) { sectionMeasure(data) }
            .frame(maxWidth:CGFloat(fit.maxWidth))
            .frame(maxWidth:.infinity)
        }
        .coordinateSpace(name:Self.contentSpace)
    }

    /// Home's own large title: not at accessibility sizes (the bar's is), nor once the bar's small
    /// one has taken over.
    func showsLargeTitle(_ step: HomeCompaction) -> Bool {
        !typeSize.isAccessibilitySize && !step.usesInlineTitle
    }

    func roomLine(_ data: HomeData) -> some View {
        ClearRoomLine(dorm:data.signedIn ? data.dorm : nil, signedIn:data.signedIn, refreshing:data.refreshing)
    }

    @ViewBuilder func setupCard(_ data: HomeData, titleOnly: Bool = false) -> some View {
        let dormSet = SetupChecklist.isDormSet(dorm:data.dorm, confirmedDorm:confirmedDorm,
                                               controllerBound:data.shower != .unconfigured)
        if let detail = HomeSetupCard.detail(signedIn:data.signedIn, dormSet:dormSet,
                                             laundryEnabled:data.laundryEnabled, laundryBound:data.laundryBound) {
            ClearSetupCard(detail:detail, titleOnly:titleOnly) { navigator.push(.setupChecklist) }
        }
    }

    /// Pull to refresh: the school's numbers, then the washer.
    func pull() async {
        // The sample reads nothing: the pull only shows.
        if sample.isActive { try? await Task.sleep(for:.milliseconds(700)); return }
        await campus.refresh(force:true)
        await laundry.refresh(force:true)
    }
}
