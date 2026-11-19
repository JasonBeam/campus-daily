import Foundation
import Core

/// Settings › 高级 › 重置校日常. The clear list itself is `AppReset` in Core; this
/// puts the running models in step before and after it, and tells the home screen to start over.
/// Clears the `CampusServices` it is given: the live app's (`shared`), or a sample's (which never
/// resets: 重置校日常 is blocked there, and it would clear only the sample's memory).
@MainActor final class AppResetter: ObservableObject {
    static let shared = AppResetter(services:AppEnvironment.live, reminders:.shared, activities:.shared,
                                    sharedPreferences:AppEnvironment.sharedPreferences)
    private let services: CampusServices
    private let reminders: Reminders
    private let activities: ShowerActivityController?
    private let sharedPreferences: AppReset.SharedPreferences?

    init(services: CampusServices, reminders: Reminders, activities: ShowerActivityController?,
         sharedPreferences: AppReset.SharedPreferences?) {
        self.services = services
        self.reminders = reminders
        self.activities = activities
        self.sharedPreferences = sharedPreferences
    }
    /// Bumped after each completed reset: the home screen closes settings and opens the guide.
    @Published private(set) var completed = 0
    @Published private(set) var running = false
    /// A reset finished and the first-run setup is still to open: taken (`takeSetup`) once, by the
    /// root of the theme now shown. A reset from 清爽 brings 暖橙's root up in the middle of it
    /// (the theme is cleared), so 清爽's root, about to go, leaves it to 暖橙's (`ResetSetupDue`).
    @Published private(set) var setupDue = ResetSetupDue()

    /// The setup is `root`'s to open; false when none is due or `root` isn't the theme shown.
    func takeSetup(root: AppTheme, current: AppTheme) -> Bool {
        setupDue.take(root:root, current:current)
    }

    /// Not while a shower runs or its settlement still needs checking, with an unfinished
    /// laundry order, while a record can't be read, or while a controller check runs.
    static func lock(shower: ShowerModel, laundry: LaundryModel) -> AppReset.Lock? {
        if shower.busy && !shower.storageBlocked && !laundry.storageBlocked { return .showering }
        return AppReset.lock(shower:shower.state, laundry:laundry.checkout?.phase, laundryBusy:laundry.checkoutBusy,
                             recordsUnreadable:shower.storageBlocked || laundry.storageBlocked,
                             checkingController:shower.inspecting)
    }

    /// Files the app wrote (the imported hot-water file, the laundry cache, the TestFlight debug
    /// log and its salt, the crash reports not sent yet, what older builds left:
    /// the hot-water diagnostics and their export, the Bluetooth scan note). The bundled hot-water
    /// parameters are app resources and stay.
    private var files: [URL] {
        guard let support = services.applicationSupport else { return [] }
        return ["Water", "LaundryCache", "WaterSession", FileDebugLog.folderName].map { support.appendingPathComponent($0, isDirectory:true) }
            + [CrashReportsLaunch.pendingFolder(in:support)]
            + [RetiredDiagnostics.exportFolder(in:FileManager.default.temporaryDirectory)]
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

    private var marker: ResetMarker { services.resetMarker }

    /// The models' locks, then the stored records (the models may still be loading at launch).
    private func anyLock(shower: ShowerModel, laundry: LaundryModel) -> AppReset.Lock? {
        Self.lock(shower:shower, laundry:laundry) ?? AppReset.storedLock(store:services.secureStore)
    }

    /// `AppReset.run`: marker, lock, sign out, clear, reload. Returns the lock that stopped it
    /// (nil = reset done).
    @discardableResult
    func reset(campus: CampusModel, shower: ShowerModel, laundry: LaundryModel, theme: ThemeStore) async throws -> AppReset.Stop? {
        guard !running else { return nil }
        running = true
        defer { running = false }
        let stopped = try await AppReset.run(marker:marker, now:Date(),
                                             lock:{ self.anyLock(shower:shower, laundry:laundry) },
                                             signOut:{ await campus.signOutForReset() },
                                             clear:clear, reload:{ await self.reload(campus:campus, shower:shower, laundry:laundry, theme:theme) },
                                             resync:{ self.resync(campus:campus, shower:shower) })
        if stopped == nil { finished() }
        return stopped
    }

    /// At launch: finish a reset the app was killed in the middle of (or say why not).
    func resumeIfInterrupted(campus: CampusModel, shower: ShowerModel, laundry: LaundryModel, theme: ThemeStore) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let resumed: AppReset.Resumed?
        do {
            resumed = try await AppReset.resume(marker:marker, now:Date(),
                                                lock:{ self.anyLock(shower:shower, laundry:laundry) },
                                                signOut:{ await campus.signOutForReset() },
                                                clear:clear, reload:{ await self.reload(campus:campus, shower:shower, laundry:laundry, theme:theme) },
                                                resync:{ self.resync(campus:campus, shower:shower) })
        } catch {
            resumeFailed = AppErrorText.text(error)
            return
        }
        switch resumed {
        case .completed?: finished()
        case .stopped(let stop)?: resumeStopped = stop
        case .abandoned?: resumeFailed = Self.abandonedText
        case nil: break
        }
    }

    private func finished() {
        completed += 1
        setupDue.resetFinished()
    }

    private func clear() throws {
        // The log's lines and salt in memory too, not only its folder (below).
        services.debugLog.clear()
        try AppReset.clear(store:services.secureStore, preferences:services.defaults,
                           preferencesDomain:Bundle.main.bundleIdentifier ?? "",
                           shared:sharedPreferences, files:files)
    }

    private func reload(campus: CampusModel, shower: ShowerModel, laundry: LaundryModel, theme: ThemeStore) async {
        campus.reload()
        theme.reload()
        await shower.reloadAfterReset()
        laundry.reloadAfterReset()
        reminders.clearAfterReset()
        activities?.endAll()
        services.sharedDidChange()
    }

    /// Stopped after the sign-out: only the school side changed. The shower may be running, so
    /// its Live Activity and 「还没结束洗澡？」 follow its record; laundry reminders stay.
    private func resync(campus: CampusModel, shower: ShowerModel) {
        campus.reload()
        let state = shower.state
        let plan = AppReset.Resync(shower:state, now:Date())
        activities?.apply(plan.showerActivity)
        reminders.syncShower(started:plan.showerReminderStart)
        services.sharedDidChange()
    }

    #if DEBUG
    /// Demo settings: show what follows a reset without clearing anything.
    func finishDemo() { finished() }
    #endif
}
