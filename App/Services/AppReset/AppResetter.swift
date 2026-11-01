import Foundation
import WidgetKit
import Core

/// Settings › 高级 › 重置校日常. The clear list itself is `AppReset` in Core; this
/// puts the running models in step before and after it, and tells the home screen to start over.
@MainActor final class AppResetter: ObservableObject {
    static let shared = AppResetter()
    /// Bumped after each completed reset: the home screen closes settings and opens the guide.
    @Published private(set) var completed = 0
    @Published private(set) var running = false

    /// Not while a shower runs or its settlement still needs checking, with an unfinished
    /// laundry order, while a record can't be read, or while a controller check runs.
    static func lock(shower: ShowerModel, laundry: LaundryModel) -> AppReset.Lock? {
        if shower.busy && !shower.storageBlocked && !laundry.storageBlocked { return .showering }
        return AppReset.lock(shower:shower.state, laundry:laundry.checkout?.phase, laundryBusy:laundry.checkoutBusy,
                             recordsUnreadable:shower.storageBlocked || laundry.storageBlocked,
                             checkingController:shower.inspecting)
    }

    /// Files the app wrote (the imported hot-water file and diagnostics, the laundry and Bluetooth
    /// caches). The bundled hot-water parameters are app resources and stay.
    static var files: [URL] {
        let support = FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask)[0]
        return ["Water", "LaundryCache", "WaterSession"].map { support.appendingPathComponent($0, isDirectory:true) }
            + [ShowerDiagnosticReport.exportFolder]
    }

    /// A reset left unfinished by the last run of the app was found at launch and stopped by a
    /// lock: nothing was cleared (beyond the sign-out, if it had run). The home screen says so.
    @Published var resumeStopped: AppReset.Stop?
    /// That reset was finished at launch and failed (something could not be deleted), or was
    /// too old to finish: what the home screen says. The marker is gone, so nothing clears
    /// later on its own.
    @Published var resumeFailed: String?

    /// A reset killed long enough ago that it was dropped, not finished, at launch.
    static let abandonedText = "上次重置没做完，再试一次。"

    static var marker: ResetMarker { ResetMarker(store:AppEnvironment.store) }

    /// The models' locks, then the stored records (the models may still be loading at launch).
    static func anyLock(shower: ShowerModel, laundry: LaundryModel) -> AppReset.Lock? {
        lock(shower:shower, laundry:laundry) ?? AppReset.storedLock(store:AppEnvironment.store)
    }

    /// `AppReset.run`: marker, lock, sign out, clear, reload. Returns the lock that stopped it
    /// (nil = reset done).
    @discardableResult
    func reset(campus: CampusModel, shower: ShowerModel, laundry: LaundryModel) async throws -> AppReset.Stop? {
        guard !running else { return nil }
        running = true
        defer { running = false }
        let stopped = try await AppReset.run(marker:Self.marker, now:Date(),
                                             lock:{ Self.anyLock(shower:shower, laundry:laundry) },
                                             signOut:{ await campus.signOutForReset() },
                                             clear:Self.clear, reload:{ await Self.reload(campus:campus, shower:shower, laundry:laundry) },
                                             resync:{ Self.resync(campus:campus, shower:shower) })
        if stopped == nil { completed += 1 }
        return stopped
    }

    /// At launch: finish a reset the app was killed in the middle of (or say why not).
    func resumeIfInterrupted(campus: CampusModel, shower: ShowerModel, laundry: LaundryModel) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let resumed: AppReset.Resumed?
        do {
            resumed = try await AppReset.resume(marker:Self.marker, now:Date(),
                                                lock:{ Self.anyLock(shower:shower, laundry:laundry) },
                                                signOut:{ await campus.signOutForReset() },
                                                clear:Self.clear, reload:{ await Self.reload(campus:campus, shower:shower, laundry:laundry) },
                                                resync:{ Self.resync(campus:campus, shower:shower) })
        } catch {
            resumeFailed = AppErrorText.text(error)
            return
        }
        switch resumed {
        case .completed?: completed += 1
        case .stopped(let stop)?: resumeStopped = stop
        case .abandoned?: resumeFailed = Self.abandonedText
        case nil: break
        }
    }

    private static func clear() throws {
        // The in-memory diagnostics first: the next event would write them all back.
        ShowerDiagnosticReport.clearMemory()
        try AppReset.clear(store:AppEnvironment.store, preferences:.standard,
                           preferencesDomain:Bundle.main.bundleIdentifier ?? "", files:files)
    }

    private static func reload(campus: CampusModel, shower: ShowerModel, laundry: LaundryModel) async {
        campus.reload()
        await shower.reloadAfterReset()
        laundry.reloadAfterReset()
        Reminders.shared.clearAfterReset()
        ShowerActivityController.shared.endAll()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Stopped after the sign-out: only the school side changed. The shower may be running, so
    /// its Live Activity and 「还没结束洗澡？」 follow its record; laundry reminders stay.
    private static func resync(campus: CampusModel, shower: ShowerModel) {
        campus.reload()
        let state = shower.state
        let plan = AppReset.Resync(shower:state, now:Date())
        ShowerActivityController.shared.apply(plan.showerActivity)
        Reminders.shared.syncShower(started:plan.showerReminderStart)
        WidgetCenter.shared.reloadAllTimelines()
    }

    #if DEBUG
    /// Demo settings: show what follows a reset without clearing anything.
    func finishDemo() { completed += 1 }
    #endif
}
