import SwiftUI
import Core

/// The page for a route, on any of 清爽's stacks. 清爽's own pages for the shower, laundry and
/// first-run setup; the list and form pages both themes share for the rest.
struct ClearDestination: View {
    let route: ClearRoute
    @EnvironmentObject private var campus: CampusModel
    @Environment(ClearNavigator.self) private var navigator

    var body: some View {
        switch route {
        case .shower: ClearShowerPage()
        case .laundry: ClearLaundryPage()
        case .washerSetup: WasherSetupView(onDone:washerSetupDone)
        case .power: if campus.powerConfigured { CampusRechargeView(kind:.electricity) } else { CampusPowerSetupView() }
        case .powerSetup: CampusPowerSetupView()
        case .card:
            #if DEBUG
            CampusRechargeView(kind:.card, demoBlocked:navigator.rechargeBlockedDemo)
            #else
            CampusRechargeView(kind:.card)
            #endif
        case .account:
            #if DEBUG
            AccountView(preview:navigator.demo)
            #else
            AccountView()
            #endif
        case .dorm: CampusOnboardingView()
        case .theme:
            #if DEBUG
            ThemeSettingsView(preview:navigator.demo)
            #else
            ThemeSettingsView()
            #endif
        case .advanced:
            #if DEBUG
            AdvancedSettingsView(preview:navigator.demo)
            #else
            AdvancedSettingsView()
            #endif
        case .setupChecklist: ClearSetupChecklist(inSheet:false)
        }
    }

    /// Saved or switched: back a page; on 日常 opened from home itself, on to 洗衣.
    private func washerSetupDone() {
        guard navigator.tab == .home else { navigator.pop(); return }
        navigator.homePath = WasherSetupExit.path(navigator.homePath, setup:.washerSetup, laundry:.laundry)
    }
}
