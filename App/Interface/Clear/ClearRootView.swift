import SwiftUI
import Core

/// The page tree of 清爽: a tab bar with 日常, 记录 and 设置, each tab its own stack of
/// `ClearRoute`s. Its pages navigate through `ClearNavigator`; what is not a page's (links,
/// notification taps, the shower page, the sheets over the tab bar) is handled here
/// (`ClearRootView+Routing`). A theme switch builds this tree anew: 日常, every stack at its root.
struct ClearRootView: View {
    @EnvironmentObject var shower: ShowerModel
    @EnvironmentObject var campus: CampusModel
    @EnvironmentObject var laundry: LaundryModel
    @Environment(\.scenePhase) var phase
    @Environment(ThemeStore.self) var themeStore
    @Environment(SampleMode.self) var sample
    /// The graph's services (`CampusScene`): `@AppStorage` here is on their preferences.
    @Environment(\.campusServices) var services
    @State var navigator = ClearNavigator()
    @State var successTick = 0
    /// The newest link or login-after-the-sample: an older one still waiting for a sheet is dropped.
    @State var destination = RootDestination()
    @EnvironmentObject var reminders: Reminders
    /// Last laundry order whose done panel was shown (once per order, shared with 暖橙).
    @AppStorage("laundryDoneShownOrder") var laundryDoneShown = ""
    #if DEBUG
    @State var activityPreview: LaundryActivityPreview.Kind?
    @State var widgetPreview: WidgetPreview.Page?
    /// campusdaily://demo/login-loading: the sign-in sheet's opening state, nothing loaded.
    @State var loginDemo = false
    /// Bumped by a records demo: the 记录 tab starts again from it.
    @State var recordsDemoRun = 0
    #endif

    /// Tests: told this root's navigator once the root appears (nil in the app).
    var navigatorShown: ((ClearNavigator) -> Void)?

    init(navigatorShown: ((ClearNavigator) -> Void)? = nil) { self.navigatorShown = navigatorShown }

    var data: HomeData { navigator.data(campus:campus, shower:shower, laundry:laundry) }

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection:$navigator.tab) {
            NavigationStack(path:$navigator.homePath) {
                ClearHomeView().navigationDestination(for:ClearRoute.self) { ClearDestination(route:$0) }
            }
            .tabItem { Label("日常", systemImage:"square.grid.2x2") }
            .tag(ClearNavigator.Tab.home)
            NavigationStack(path:$navigator.recordsPath) {
                recordsTab.navigationDestination(for:ClearRoute.self) { ClearDestination(route:$0) }
            }
            .tabItem { Label("记录", systemImage:"clock.arrow.circlepath") }
            .tag(ClearNavigator.Tab.records)
            NavigationStack(path:$navigator.settingsPath) {
                ClearSettingsTab().navigationDestination(for:ClearRoute.self) { ClearDestination(route:$0) }
            }
            .tabItem { Label("设置", systemImage:"slider.horizontal.3") }
            .tag(ClearNavigator.Tab.settings)
        }
        .sensoryFeedback(.success, trigger:successTick)
        .accountSwitchAlert { openShowerSetup() }
        .sheet(isPresented:$navigator.relogin) { SchoolReloginSheet().typesettingLanguage(Theme.typesetting) }
        // Closed because the sample opened over it: not seen (`QuickSetupSeen`).
        .sheet(item:$navigator.setup, onDismiss:{ QuickSetupSeen.closed(in:services.defaults, coveredBySample:sample.isActive) }) { request in
            // .id: a new request (or a new row on this one) starts the checklist again, with its row pushed.
            #if DEBUG
            ClearSetupChecklist(start:request.start).onRow { navigator.setup?.guide.moved(to:$0) }.id(request.guide.contentID).typesettingLanguage(Theme.typesetting)
                .onOpenURL { handleDemo($0) }
            #else
            ClearSetupChecklist(start:request.start).onRow { navigator.setup?.guide.moved(to:$0) }.id(request.guide.contentID).typesettingLanguage(Theme.typesetting)
            #endif
        }
        .sheet(isPresented:Binding(get:{ navigator.panel != nil }, set:{ if !$0 { navigator.panel = nil } })) {
            ClearLaundryDonePanel()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .typesettingLanguage(Theme.typesetting)
        }
        #if DEBUG
        .fullScreenCover(item:$activityPreview) { kind in
            LaundryActivityPreview(kind:kind).onTapGesture { activityPreview = nil }.onOpenURL { handleDemo($0) }
        }
        .sheet(isPresented:$loginDemo) {
            CampusLoginSheet(receive:{ _ in }, holdOpening:true)
        }
        .fullScreenCover(item:$widgetPreview) { page in
            WidgetPreview(page:page.number).onTapGesture { widgetPreview = nil }.onOpenURL { handleDemo($0) }
        }
        #endif
        .modifier(CampusRootHooks(demo:isDemo, root:.clear, firstRun:{ navigator.openSetup() }, afterReset:afterReset))
        .sampleChrome()
        .onChange(of:sample.isActive, initial:true) { _, active in followSample(active) }
        .onChange(of:sample.loginDue, initial:true) { _, due in openLoginAfterSample(due) }
        // 记录 shows one person's records: back to its root when they sign out or someone else signs in.
        .onChange(of:campus.personChanges) { _, _ in navigator.popToRoot(.records) }
        .onChange(of:shower.page.presented, initial:true) { _, up in followShowerPage(up) }
        .onChange(of:shower.page.page?.phase) { _, _ in followShowerPage(shower.page.presented) }
        .onChange(of:shower.pageWanted) { _, _ in followShowerPage(shower.page.presented) }
        .onChange(of:shower.reviewRequested) { _, requested in
            guard requested else { return }
            shower.reviewRequested = false
            // 去核对: the same page, now on the record to check.
            showShowerPage()
        }
        .onChange(of:navigator.homePath) { old, new in showerPageLeft(old:old, new:new) }
        .onChange(of:data.laundryDone, initial:true) { _, done in presentLaundryDone(done) }
        // A done panel that arrived while another was up is shown once that one closes.
        .onChange(of:navigator.panel == nil) { _, clear in if clear { presentLaundryDone(data.laundryDone) } }
        .modifier(ReminderHooks(open:follow, homeClear:homeClear))
        // The widget's links, dispatched by the app (`SampleMode.open`): this root opens them
        // only when it is the live one.
        .onChange(of:sample.pendingLink, initial:true) { _, _ in takePendingLink() }
        #if DEBUG
        .onOpenURL { if RootLink($0) == nil { handleDemo($0) } }
        #endif
        .environment(navigator)
        .onAppear { navigatorShown?(navigator) }
    }

    @ViewBuilder var recordsTab: some View {
        #if DEBUG
        ClearRecordsTab().id(recordsDemoRun)
        #else
        ClearRecordsTab()
        #endif
    }

    /// Synthetic data is on screen (a DEBUG demo, or the sample in Release too).
    var isDemo: Bool { navigator.demo != nil || sample.isActive }
}
