import SwiftUI
import Core

@main struct XiaoRiChangApp: App {
    /// The live models, stores and services. Shown unless the sample is on.
    private let live: CampusGraph
    /// 「先看看示例」: in memory only, so every launch starts outside it. On, the scene shows a
    /// graph of its own (`SampleScene`) instead of `live`.
    @State private var sample: SampleMode
    /// Which page shows the sample's blocked message (`SampleChrome`).
    @State private var sampleAlerts = SampleAlertStack()
    init() {
        // Before any model reads: older builds kept items in the other keychain group.
        SharedKeychain.migrateItemGroups()
        let sample = SampleMode(gate:ShowerModel.liveGate)
        _sample = State(initialValue:sample)
        live = CampusGraph.live()
        // A reminder prompt queued on the live home waits while the sample covers it.
        live.reminders.held = { [weak sample] in sample?.isActive ?? false }
        ShowerIntentGate.sample = sample
        // FinishShowerLiveIntent (Live Activity button) runs in this process, on the live session:
        // shown over the sample, it leaves it first and the live app stays up (`LiveShowerFinish`).
        ShowerActivityBridge.finish = { [weak sample] in
            AppEnvironment.live.debugNav.from(.liveActivity)
            _ = try await LiveShowerFinish.run(sample:sample) { try await ShowerModel.shared.run(start:false) }
        }
        // Notification delegate must be set before launch finishes, so a tapped banner is routed
        // (`Reminders.shared`, set up by `live`).
    }
    var body: some Scene {
        WindowGroup {
            ZStack {
                if let services = sample.services {
                    SampleScene(services:services, theme:live.theme.theme).id(services.id)
                } else {
                    CampusScene(graph:live)
                }
            }
            .environment(sample).environment(sampleAlerts)
            .modifier(LiveAppHooks(campus:live.campus, laundry:live.laundry, reminders:live.reminders, sample:sample))
        }
        // Background campus read: low power / card reminders and a fresh widget (the live graph's).
        .backgroundTask(.appRefresh(BackgroundRefresh.refreshTask)) { await BackgroundRefresh.run() }
    }
}

/// The live app's own events, whichever graph is shown: launch reads, links, the scene phase.
/// While the sample is on, nothing here reaches a sample page, and the live models are not read
/// from it.
private struct LiveAppHooks: ViewModifier {
    @ObservedObject var campus: CampusModel
    @ObservedObject var laundry: LaundryModel
    let reminders: Reminders
    let sample: SampleMode
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .onChange(of:campus.room, initial:true) { ShowerActivityController.shared.dorm = Theme.dorm(campus.room) ?? "" }
            .task {
                await campus.dropCampusWideMeter()
                campus.matchPowerAutomatically(.launch)
                await campus.refresh()
                await laundry.refresh()
            }
            // The one place links are dispatched (`SampleMode.open`): the widget's go to the live
            // root (`takePendingLink`), never to a sample page; another app's answer (Alipay) is
            // the live app's, after the sample if it is on.
            .onOpenURL { url in
                if sample.open(url) == .live, url.scheme != "campusdaily" { answer(url) }
            }
            .onChange(of:sample.isActive) { _, active in
                guard !active else { return }
                for url in sample.takeHeldLinks() { answer(url) }
            }
            .onChange(of:phase) { _, value in
                // The live app's own work runs as usual while the sample is shown: it reaches no
                // sample page (the sample runs on its own services and draws its own graph).
                if value == .background { BackgroundRefresh.scheduleRefresh() }
                if value == .active {
                    // Launched before the first unlock (pre-warmed), the Keychain could not be read:
                    // read it again now, before the home's foreground refresh runs.
                    campus.reload()
                    Task { await reminders.refreshAuthorization() }
                    // Back from Alipay without a callback URL (checkout links): read the order.
                    Task { await laundry.refreshOrder() }
                }
            }
    }

    private func answer(_ url: URL) {
        AlipayBridge.shared.handle(url)
        Task { await laundry.refreshOrder() }
    }
}
