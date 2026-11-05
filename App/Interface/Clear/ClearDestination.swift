import SwiftUI
import Core

/// The page for a route, on any of 清爽's stacks. 清爽's own pages for the shower, laundry and
/// first-run setup; the list and form pages both themes share for the rest.
struct ClearDestination: View {
    let route: ClearRoute
    @EnvironmentObject private var campus: CampusModel
    @Environment(ClearNavigator.self) private var navigator
    @Environment(SampleMode.self) private var sample

    var body: some View {
        if sample.isActive, let data = navigator.demo { sampleBody(data) } else { liveBody }
    }

    /// The sample's pages on its data: 余额 and 电量 are its own (the live ones are the school's
    /// web pages); the rows that need an account or a device are blocked before they push.
    @ViewBuilder private func sampleBody(_ data: HomeData) -> some View {
        switch route {
        case .card: SampleCardPage(data:data)
        case .power, .powerSetup: SamplePowerPage(data:data)
        case .theme: ThemeSettingsView(preview:data)
        case .advanced: AdvancedSettingsView(preview:data)
        case .laundry, .washerSetup: ClearLaundryPage()
        case .shower, .account, .dorm, .setupChecklist: ClearShowerPage()
        }
    }

    @ViewBuilder private var liveBody: some View {
        switch route {
        case .shower: ClearShowerPage()
        case .laundry: ClearLaundryPage()
        case .washerSetup: WasherSetupView(onDone:washerSetupDone)
        case .power: if campus.powerConfigured { CampusRechargeView(kind:.electricity) } else { CampusPowerSetupView() }
        case .powerSetup: CampusPowerSetupView()
        case .card: CampusRechargeView(kind:.card, demoBlocked:navigator.rechargeBlockedDemo)
        case .account: AccountView(preview:navigator.demo)
        case .dorm: CampusOnboardingView()
        case .theme: ThemeSettingsView(preview:navigator.demo)
        case .advanced: AdvancedSettingsView(preview:navigator.demo)
        case .setupChecklist: ClearSetupChecklist(inSheet:false)
        }
    }

    /// Saved or switched: back a page; on 日常 opened from home itself, on to 洗衣.
    private func washerSetupDone() {
        guard navigator.tab == .home else { navigator.pop(); return }
        navigator.homePath = WasherSetupExit.path(navigator.homePath, setup:.washerSetup, laundry:.laundry)
    }
}
