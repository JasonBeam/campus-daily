import SwiftUI
import WidgetKit
import Core

/// One graph of the app's models, all on one `CampusServices`: the live app's (`live`, on the
/// Keychain, the preferences, the App Group, the network and Bluetooth), or a sample's
/// (`sample(on:theme:)`, every model new, on the sample's own services). A scene shows one graph
/// at a time (`CampusScene`): while 「先看看示例」 is on the live graph is in no page's environment.
@MainActor final class CampusGraph: ObservableObject {
    let services: CampusServices
    let shower: ShowerModel
    let campus: CampusModel
    let laundry: LaundryModel
    let reminders: Reminders
    let resetter: AppResetter
    let theme: ThemeStore

    private init(services: CampusServices, shower: ShowerModel, campus: CampusModel, laundry: LaundryModel,
                 reminders: Reminders, resetter: AppResetter, theme: ThemeStore) {
        self.services = services; self.shower = shower; self.campus = campus; self.laundry = laundry
        self.reminders = reminders; self.resetter = resetter; self.theme = theme
    }

    /// The live app's: its models are the process's (Live Activity buttons, intents and the
    /// background refresh run on them too). Built once, after the keychain migration.
    static func live() -> CampusGraph {
        let shower = ShowerModel.shared, campus = CampusModel.shared, reminders = Reminders.shared
        let laundry = LaundryModel(services:AppEnvironment.live, reminders:reminders, activities:.shared)
        reminders.campusSnapshot = { CampusModel.shared.snapshot }
        // The theme is stored in the App Group, where the widget and the Live Activities read
        // it. It won't change while a shower or laundry run is going on.
        let theme = ThemeStore(preference:ThemePreference(storage:ThemePreference.sharedStorage()), lock:AppEnvironment.sharedLock,
                               didChange:{ WidgetCenter.shared.reloadAllTimelines() }) { [weak laundry] in
            ThemeLock.lock(shower:ShowerModel.shared.state, laundry:laundry?.checkout?.phase)
        }
        return CampusGraph(services:AppEnvironment.live, shower:shower, campus:campus, laundry:laundry,
                           reminders:reminders, resetter:.shared, theme:theme)
    }

    /// A sample's, on `services` (`CampusServices.sample()`): no model, store or service of the
    /// live graph is passed in, only the theme shown when it opens (a value), so the sample
    /// starts on the same theme.
    static func sample(on services: CampusServices, theme shown: AppTheme) -> CampusGraph {
        let reminders = Reminders.sample(defaults:services.defaults)
        let shower = ShowerModel(services:services, reminders:reminders, activities:nil)
        let campus = CampusModel(services:services, stack:services.schoolStack(), reminders:reminders) { [weak shower] in shower }
        let laundry = LaundryModel(services:services, reminders:reminders, activities:nil)
        reminders.campusSnapshot = { [weak campus] in campus?.snapshot ?? .empty }
        let resetter = AppResetter(services:services, reminders:reminders, activities:nil, sharedPreferences:nil)
        let preference = ThemePreference(storage:services.sharedPreferences ?? services.defaults)
        try? preference.set(shown, under:UnsharedLock())
        let theme = ThemeStore(preference:preference, lock:UnsharedLock(), didChange:services.sharedDidChange) { [weak shower, weak laundry] in
            ThemeLock.lock(shower:shower?.state, laundry:laundry?.checkout?.phase)
        }
        return CampusGraph(services:services, shower:shower, campus:campus, laundry:laundry,
                           reminders:reminders, resetter:resetter, theme:theme)
    }
}

private struct CampusServicesKey: EnvironmentKey {
    /// Outside a scene: a sample's, which reaches nothing (never the live services by default).
    static let defaultValue = CampusServices.sample()
}

extension EnvironmentValues {
    /// The services of the graph the page is drawn on (`CampusScene`): its preferences and clients.
    var campusServices: CampusServices {
        get { self[CampusServicesKey.self] }
        set { self[CampusServicesKey.self] = newValue }
    }
}

/// The pages on one graph: its models, reminders, resetter and theme in the environment, its
/// services as `\.campusServices`, and its preferences under every `@AppStorage`.
struct CampusScene: View {
    let graph: CampusGraph
    var body: some View {
        CampusRootView()
            .environmentObject(graph.shower).environmentObject(graph.campus).environmentObject(graph.laundry)
            .environmentObject(graph.reminders).environmentObject(graph.resetter)
            .environment(graph.theme)
            .environment(\.campusServices, graph.services)
            .defaultAppStorage(graph.services.defaults)
    }
}

/// 「先看看示例」's scene: a graph of its own, built once for these services (one sample) and
/// gone with it.
struct SampleScene: View {
    @StateObject private var graph: CampusGraph
    init(services: CampusServices, theme: AppTheme) {
        _graph = StateObject(wrappedValue:CampusGraph.sample(on:services, theme:theme))
    }
    var body: some View { CampusScene(graph:graph) }
}
