import Foundation
import BackgroundTasks

/// Background campus read: low power / card reminders and a fresh widget.
enum BackgroundRefresh {
    /// The id Info.plist permits (`$(APP_BUNDLE_IDENTIFIER).refresh`, filled in at build time),
    /// so the task follows the bundle id the app is built for.
    nonisolated static let refreshTask = (Bundle.main.object(forInfoDictionaryKey:"BGTaskSchedulerPermittedIdentifiers") as? [String])?.first
        ?? (Bundle.main.bundleIdentifier ?? "") + ".refresh"

    /// Asks for a campus read in the background (~hourly, the system decides).
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier:refreshTask)
        request.earliestBeginDate = Date().addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The `.appRefresh` task body: book the next run, then read.
    @MainActor static func run() async {
        scheduleRefresh()
        await CampusModel.shared.refresh(force:true, inBackground:true)
    }
}
