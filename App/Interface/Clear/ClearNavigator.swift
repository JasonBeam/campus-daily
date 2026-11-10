import SwiftUI
import Observation
import Core

/// 清爽's navigation, shared by its root and its pages: which tab is selected, each tab's stack,
/// and the sheets hosted on the tab bar root. The root owns one and puts it in the environment;
/// pages read it with `@Environment(ClearNavigator.self) private var navigator`.
///
/// For pages:
/// - push a page on the stack the page is on: `navigator.push(.laundry)` or
///   `NavigationLink(value:ClearRoute.laundry)` (every stack maps `ClearRoute` with `ClearDestination`);
/// - switch tab: `navigator.select(.records)` (「全部 ›」 on home); open a page on a tab keeping what is
///   open there: `navigator.open(.laundry, in:.home, laundry:)` (记录's rows); the shower page on
///   日常: `navigator.showShowerPage(laundry:)`;
/// - go back: `@Environment(\.dismiss)` or `navigator.pop()`; to a tab's root: `navigator.popToRoot()`;
/// - the first-run checklist as a sheet: `navigator.openSetup()`; the sign-in sheet or
///   Settings › 学校账号 from the expired-login line: `navigator.signInAgain(_:)`;
/// - what home shows: `navigator.data(campus:shower:laundry:)` (the DEBUG demo when one is up).
///
/// The shower page is the root's: when the shower model asks for it (`shower.page.presented`)
/// the root selects 日常 and pushes `.shower` (not twice). Popping it while water runs collapses
/// it, as 暖橙's ⌄ does; in the other phases the page keeps itself up (hidden back button and tab bar).
@MainActor @Observable final class ClearNavigator {
    enum Tab: Hashable { case home, records, settings }

    /// One presentation of the first-run checklist; a new id replaces the current one. Asked
    /// for while one is up (`openSetup`), the same one is kept (`GuideRequest`).
    struct SetupRequest: Identifiable {
        var guide: GuideRequest<ClearSetupRow>
        #if DEBUG
        /// campusdaily://demo/onboard/...: the step pages show these values and send nothing.
        var preview: OnboardingView.Preview?
        #endif
        var id: UUID { guide.id }
        /// The row pushed when it opens (campusdaily://login: 学校账号).
        var start: ClearSetupRow? { guide.start }

        #if DEBUG
        init(start: ClearSetupRow?, preview: OnboardingView.Preview? = nil) {
            guide = GuideRequest(start:start); self.preview = preview
        }
        #else
        init(start: ClearSetupRow?) { guide = GuideRequest(start:start) }
        #endif
    }

    var tab: Tab = .home
    /// `nav.open`'s reasons (the graph's, set by the root). Every route here that a plain tap on
    /// a link doesn't make says why (`from`), for the pages it opens.
    @ObservationIgnored private(set) var debugNav = DebugNav(log:NoDebugLog())
    var homePath: [ClearRoute] = []
    var recordsPath: [ClearRoute] = []
    var settingsPath: [ClearRoute] = []
    /// The first-run checklist sheet.
    var setup: SetupRequest?
    /// The sign-in sheet, from the expired-login line.
    var relogin = false
    /// The laundry-done sheet (`ClearLaundryDonePanel` reads it).
    var panel: SettlementResult?

    /// DEBUG demo data (campusdaily://demo/...); nil = live models.
    var demo: HomeData?
    var laundryDemo: LaundryDemo?
    var recordsDemo: RecordsDemo?

    func path(_ tab: Tab) -> [ClearRoute] {
        switch tab {
        case .home: homePath
        case .records: recordsPath
        case .settings: settingsPath
        }
    }

    func setPath(_ routes: [ClearRoute], _ tab: Tab) {
        switch tab {
        case .home: homePath = routes
        case .records: recordsPath = routes
        case .settings: settingsPath = routes
        }
    }

    /// The root's, from its services; once.
    func attach(_ nav: DebugNav) { if debugNav !== nav { debugNav = nav } }

    /// `entry` for these pages, and for `tab`'s root when it is not the one selected now.
    private func mark(_ entry: DebugEntry, _ routes: [ClearRoute], tab: Tab? = nil, unlessPending: Bool = false) {
        var pages = Set(routes.map(\.debugPage))
        if let tab, tab != self.tab { pages.insert(tab.debugPage) }
        guard !pages.isEmpty else { return }
        debugNav.from(entry, to:pages, unlessPending:unlessPending)
    }

    /// `entry` for pages the root opens itself (a sheet, the checklist).
    func mark(_ entry: DebugEntry, pages: Set<DebugPage>) { debugNav.from(entry, to:pages) }

    /// Pushes a page on the selected tab's stack. `from`: a tap that isn't the page's own link
    /// (最近's rows); nil: the tab's entry.
    func push(_ route: ClearRoute, from entry: DebugEntry? = nil) {
        if let entry { mark(entry, [route]) }
        setPath(path(tab) + [route], tab)
    }

    /// Back one page on the selected tab.
    func pop() {
        var routes = path(tab)
        guard !routes.isEmpty else { return }
        routes.removeLast()
        setPath(routes, tab)
    }

    /// Back to a tab's root (the selected one by default).
    func popToRoot(_ tab: Tab? = nil) { setPath([], tab ?? self.tab) }

    func select(_ tab: Tab) { self.tab = tab }

    /// Selects a tab showing exactly these pages.
    func show(_ routes: [ClearRoute], in tab: Tab, from entry: DebugEntry) {
        mark(entry, routes, tab:tab)
        self.tab = tab
        setPath(routes, tab)
    }

    /// Selects a tab with this page showing, keeping the pages already open there
    /// (`PageStack.opening`): back to it when it is lower and nothing over it must stay (a top-up
    /// page, 洗衣 while an order is being paid), otherwise pushed on top.
    /// 记录's rows open 洗衣 on 日常 this way.
    func open(_ route: ClearRoute, in tab: Tab, laundry: LaundryPhase?, from entry: DebugEntry) {
        mark(entry, [route], tab:tab)
        self.tab = tab
        setPath(PageStack.opening(route, on:path(tab)) { PageStack.mayClose($0, laundry:laundry) }, tab)
    }

    /// 日常 with the shower page on top (`PageStack.showingShower`): not pushed twice, back to it
    /// when nothing over it must stay. The root's on the model's request; 记录's and 设置's rows too.
    /// `unlessPending`: the page raising itself keeps a reason given just before (a tap, a Shortcut).
    func showShowerPage(laundry: LaundryPhase?, from entry: DebugEntry, unlessPending: Bool = false) {
        mark(entry, [.shower], tab:.home, unlessPending:unlessPending)
        tab = .home
        let routes = PageStack.showingShower(on:homePath, laundry:laundry)
        if routes != homePath { homePath = routes }
    }

    /// A page that lives on 日常 (记录's showers and laundry orders): the shower page as the root
    /// shows it, any other with `open`.
    func openOnHome(_ route: ClearRoute, laundry: LaundryPhase?, from entry: DebugEntry) {
        if route == .shower { showShowerPage(laundry:laundry, from:entry) } else { open(route, in:.home, laundry:laundry, from:entry) }
    }

    /// The checklist, at `row`. Already up (first-run, then a login link just after the sample):
    /// kept, with `row` pushed on it, not presented again.
    func openSetup(at row: ClearSetupRow? = nil, from entry: DebugEntry) {
        mark(entry, pages:[.setupChecklist])
        guard var request = setup else { setup = SetupRequest(start:row); return }
        request.guide = GuideRequest.ask(row, over:request.guide)
        setup = request
    }

    /// The expired-login line: the sign-in sheet, or Settings › 学校账号 when the saved password
    /// is paused there.
    func signInAgain(_ target: HomeUpdateLine.SignInTarget) {
        switch target {
        case .signIn: mark(.updateLine, pages:[.signIn]); relogin = true
        case .account: show([.account], in:.settings, from:.updateLine)
        }
    }

    /// What home shows: the DEBUG demo when one is up, otherwise the live models.
    func data(campus: CampusModel, shower: ShowerModel, laundry: LaundryModel) -> HomeData {
        if let demo { return demo }
        return HomeData(campus:campus, shower:shower, laundry:laundry)
    }
}
