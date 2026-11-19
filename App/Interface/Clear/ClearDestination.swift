import SwiftUI
import Core

/// The page for a route, on any of 清爽's stacks. 清爽's own pages for the shower, laundry and
/// first-run setup; the list and form pages both themes share for the rest.
struct ClearDestination: View {
    let route: ClearRoute
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    @EnvironmentObject private var shower: ShowerModel
    @Environment(ClearNavigator.self) private var navigator
    @Environment(SampleMode.self) private var sample

    var body: some View {
        Group {
            if sample.isActive, let data = navigator.demo { sampleBody(data) } else { liveBody }
        }
        .navOpen(route.debugPage, from:navigator.tab.debugEntry)
    }

    /// The sample's pages on its data: 余额 and 电量 are its own (the live ones are the school's
    /// web pages); the rows that need an account or a device are blocked before they push.
    @ViewBuilder private func sampleBody(_ data: HomeData) -> some View {
        switch route {
        case .card: SampleCardPage(data:data)
        case .power: SamplePowerPage(data:data)
        case .powerSetup: ClearSampleMeterPage(data:data)
        case .theme: ThemeSettingsView(preview:data)
        case .advanced: AdvancedSettingsView(preview:data)
        case .laundryReminders: ClearLaundryReminderPage(laundryOn:data.laundryEnabled)
        case .reminders: ClearReminderPage(laundryOn:data.laundryEnabled)
        case .shortcuts: ClearShortcutsPage()
        case .laundry, .washerSetup: ClearLaundryPage()
        case .shower, .account, .dorm, .setupChecklist: ClearShowerPage()
        }
    }

    @ViewBuilder private var liveBody: some View {
        switch route {
        case .shower: ClearShowerPage()
        case .laundry: ClearLaundryPage()
        case .washerSetup: washerSetup
        case .power: if campus.powerConfigured { CampusTopUpView() } else { CampusPowerSetupView() }
        case .powerSetup: CampusPowerSetupView()
        case .card: CampusTopUpView()
        case .account: AccountView(preview:navigator.demo, places:AnyView(ClearCampusSections(data:homeData)))
        case .dorm: CampusOnboardingView()
        case .theme: ThemeSettingsView(preview:navigator.demo)
        case .advanced: AdvancedSettingsView(preview:navigator.demo)
        case .setupChecklist: ClearSetupChecklist(inSheet:false)
        case .laundryReminders: ClearLaundryReminderPage(laundryOn:navigator.demo?.laundryEnabled ?? laundry.schoolEnabled)
        case .reminders: ClearReminderPage(laundryOn:navigator.demo?.laundryEnabled ?? laundry.schoolEnabled)
        case .shortcuts: ClearShortcutsPage()
        }
    }

    /// 常用洗衣机; on demo data, the demo's machines (two saved, or signed out of U净).
    @ViewBuilder private var washerSetup: some View {
        #if DEBUG
        if let demo = navigator.demo {
            WasherSetupView(onDone:washerSetupDone, laundrySwitch:laundrySwitch,
                            preview:demo.laundryBound ? .twoSaved : WasherSetupDemo())
        } else {
            WasherSetupView(onDone:washerSetupDone, laundrySwitch:laundrySwitch)
        }
        #else
        WasherSetupView(onDone:washerSetupDone, laundrySwitch:laundrySwitch)
        #endif
    }

    private var homeData: HomeData { navigator.data(campus:campus, shower:shower, laundry:laundry) }

    /// 常用洗衣机's 「学校洗衣机」 switch (the demo's value is shown, not changed).
    private var laundrySwitch: SchoolLaundrySwitch {
        SchoolLaundrySwitch(laundry:laundry, preview:navigator.demo, previewOn:.constant(nil))
    }

    /// Saved or switched: back a page; on 日常 opened from home itself, on to 洗衣.
    private func washerSetupDone() {
        guard navigator.tab == .home else { navigator.pop(); return }
        let next = WasherSetupExit.path(navigator.homePath, setup:.washerSetup, laundry:.laundry)
        if next.last == .laundry, navigator.homePath.last != .laundry { navigator.mark(.setupDone, pages:[.laundry]) }
        navigator.homePath = WasherSetupExit.path(navigator.homePath, setup:.washerSetup, laundry:.laundry)
    }
}
