import SwiftUI
import Core

@main struct XiaoRiChangApp: App {
    @StateObject private var water = ShowerModel.shared
    @StateObject private var campus = CampusModel.shared
    @StateObject private var laundry = LaundryModel()
    init() {
        // Before any model reads: older builds kept items in the other keychain group.
        SharedKeychain.migrateItemGroups()
        // FinishShowerLiveIntent (Live Activity button) runs in this process.
        ShowerActivityBridge.finish = { try await ShowerModel.shared.run(start:false) }
        // Notification delegate must be set before launch finishes, so a tapped banner is routed.
        _ = Reminders.shared
    }
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            CampusRootView().environmentObject(water).environmentObject(campus).environmentObject(laundry)
                .onChange(of:campus.room,initial:true) { ShowerActivityController.shared.dorm = Theme.dorm(campus.room) ?? "" }
                .task {
                    await campus.dropCampusWideMeter()
                    campus.matchPowerAutomatically(.launch)
                    await campus.refresh()
                    await laundry.refresh()
                }
                .onOpenURL { if $0.scheme != "campusdaily" { AlipayBridge.shared.handle($0); Task { await laundry.refreshOrder() } } }
        }
        .onChange(of:phase) { _, value in
            if value == .background { BackgroundRefresh.scheduleRefresh() }
            if value == .active {
                Task { await Reminders.shared.refreshAuthorization() }
                // Back from Alipay without a callback URL (checkout links): read the order.
                Task { await laundry.refreshOrder() }
            }
        }
        // Background campus read: low power / card reminders and a fresh widget.
        .backgroundTask(.appRefresh(BackgroundRefresh.refreshTask)) { await BackgroundRefresh.run() }
    }
}
