import SwiftUI
import Core

extension ClearRootView {
    // MARK: Shower page

    /// The shower page is up and must not be left: connecting, settling, a result to answer.
    var showerLocked: Bool { shower.page.presented && !shower.page.mayCollapse }

    /// The shower model wants its page: 日常 selected, the page pushed there unless it is already
    /// on top. The sign-in sheet and the first-run checklist close; the laundry-done sheet stays
    /// (it is shown once per order), with the page under it.
    /// Called again on every start, reopen and page change.
    func followShowerPage(_ up: Bool) {
        guard up else { return }
        navigator.relogin = false; navigator.setup = nil
        showShowerPage(from:.pageEvent)
    }

    /// Already lower on the stack: back to it rather than a second copy, unless that would close
    /// a page that must stay (`PageStack.showingShower`). The model's own requests say
    /// `pageEvent`, unless a tap or a Shortcut said why just before.
    func showShowerPage(from entry: DebugEntry) {
        navigator.showShowerPage(laundry:laundry.checkout?.phase, from:entry, unlessPending:entry == .pageEvent)
    }

    /// The shower page was popped (its back button, a link) while the model still has it up:
    /// while water runs that collapses it, as 暖橙's ⌄; otherwise it is put back.
    func showerPageLeft(old: [ClearRoute], new: [ClearRoute]) {
        switch PageStack.showerLeft(old:old, new:new, presented:shower.page.presented, mayCollapse:shower.page.mayCollapse) {
        case .nothing: break
        case .collapse: shower.pageEvent(.collapseTapped)
        case .putBack: showShowerPage(from:.restore)
        }
    }

    // MARK: Pages

    /// Pages may be closed for a link or a notification tap: never a top-up page, nor the laundry
    /// page while an order is between creation and the end of the payment check, on any tab
    /// (`WidgetLink.mayClosePages`). Returning from the payment must find that page still there.
    var mayClosePages: Bool {
        let routes = navigator.homePath + navigator.recordsPath + navigator.settingsPath
        return WidgetLink.mayClosePages(rechargeOpen:routes.contains(.card) || routes.contains(.power),
                                        laundryOpen:routes.contains(.laundry), laundry:laundry.checkout?.phase)
    }

    /// 日常 showing these pages, under the shower page while that is up: as in 暖橙, they are
    /// there once it goes.
    func reveal(_ routes: [ClearRoute], from entry: DebugEntry) {
        var pages = Set(routes.map(\.debugPage))
        if !shower.page.presented, navigator.tab != .home { pages.insert(.home) }
        if !pages.isEmpty { navigator.mark(entry, pages:pages) }
        let routes = shower.page.presented ? routes + [.shower] : routes
        if !shower.page.presented { navigator.tab = .home }
        navigator.homePath = routes
    }

    /// Every stack back to its root and 日常 selected (the shower page stays while it is up).
    func popAll(from entry: DebugEntry) {
        navigator.recordsPath = []; navigator.settingsPath = []
        reveal([], from:entry)
    }

    /// Another tab showing these pages; while the shower page can't be left it stays selected.
    func show(_ routes: [ClearRoute], in tab: ClearNavigator.Tab, from entry: DebugEntry) {
        var pages = Set(routes.map(\.debugPage))
        if !showerLocked, navigator.tab != tab { pages.insert(tab.debugPage) }
        if !pages.isEmpty { navigator.mark(entry, pages:pages) }
        navigator.setPath(routes, tab)
        if !showerLocked { navigator.tab = tab }
    }

    /// 「去设置热水」 after an account switch: the hot-water page on 日常, or 宿舍 on 设置 while there is
    /// no binding; on the stack the user left (`PageStack.showerSetup`): never a second shower
    /// page, never closing a top-up page or 洗衣 while an order is being paid. While the shower page
    /// can't be left it stays selected.
    func openShowerSetup() {
        let target = PageStack.showerSetup(configured:shower.configured, home:navigator.homePath,
                                             settings:navigator.settingsPath, laundry:laundry.checkout?.phase)
        switch target {
        case .home(let routes): navigator.mark(.alert, pages:Set(routes.map(\.debugPage)).union(showerLocked || navigator.tab == .home ? [] : [.home]))
        case .settings(let routes): navigator.mark(.alert, pages:Set(routes.map(\.debugPage)).union(showerLocked || navigator.tab == .settings ? [] : [.settings]))
        }
        switch target {
        case .home(let routes):
            if routes != navigator.homePath { navigator.homePath = routes }
            if !showerLocked { navigator.tab = .home }
        case .settings(let routes):
            if routes != navigator.settingsPath { navigator.settingsPath = routes }
            if !showerLocked { navigator.tab = .settings }
        }
    }

    /// A notification tap: the same guard as the widget's links; laundry opens its page.
    func follow(_ route: Reminders.Route) {
        guard mayClosePages else { return }
        navigator.recordsPath = []; navigator.settingsPath = []
        reveal(route == .laundry ? [.laundry] : [], from:.notification)
    }

    /// Nothing over home: 日常 at its root, no sheet or shower page, app in front.
    var homeClear: Bool {
        var clear = phase == .active && navigator.tab == .home && navigator.homePath.isEmpty
            && navigator.setup == nil && !navigator.relogin && navigator.panel == nil && !shower.page.presented
        #if DEBUG
        clear = clear && activityPreview == nil && widgetPreview == nil
        #endif
        return clear
    }

    /// Reset finished: back to the first-run checklist as on a fresh install, no toast.
    func afterReset() {
        navigator.setup = nil; navigator.relogin = false; navigator.panel = nil
        navigator.demo = nil; navigator.laundryDemo = nil; navigator.recordsDemo = nil
        popAll(from:.reset)
        successTick += 1
        // Let a closing sheet go first, otherwise the new one is not presented.
        Task { try? await Task.sleep(for:.milliseconds(600)); navigator.openSetup(from:.reset) }
    }

    func presentLaundryDone(_ done: HomeData.LaundryDone?) {
        if navigator.demo != nil { return }
        guard let done, done.id != laundryDoneShown, navigator.panel == nil else { return }
        laundryDoneShown = done.id
        successTick += 1
        navigator.panel = .laundryDone(amount:done.amount, detail:done.detail)
    }

    // MARK: Links

    /// The widget's link (`SampleMode.takePendingLink`: never while the sample is on, so never
    /// on a sample's root), once. Just after the sample left, its sheets go first; a newer
    /// link in the meantime wins (`destination`).
    func takePendingLink() {
        guard let link = sample.takePendingLink() else { return }
        if link == .login { destination.after(600) { open(link) } } else { open(link) }
    }

    /// The widget's links (`RootLink`).
    func open(_ link: RootLink) {
        // The newest destination: an older one still waiting (`openLoginAfterSample`) is dropped.
        destination.supersede()
        guard mayClosePages else { return }
        switch link {
        case .home: popAll(from:.widget)
        // A paused automatic login (widget): 设置 › 学校账号, where the pause is explained.
        case .settings(account:true): show([.account], in:.settings, from:.widget)
        case .login:
            popAll(from:.widget)
            navigator.openSetup(at:.account, from:.widget)
        case .settings(account:false): show([], in:.settings, from:.widget)
        }
    }
}
