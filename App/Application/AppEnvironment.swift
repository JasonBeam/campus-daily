import Foundation
import Security
import WidgetKit
import Core

/// Composition root: one Keychain store, one HTTP client per service family, the school session
/// and the snapshot refresher (the only writer of the widget-shared snapshot), gathered in `live`,
/// the services the live models run on (a sample runs on `CampusServices.sample()` instead).
/// The hot-water and laundry engines are built by their models (they depend on the binding / login).
enum AppEnvironment {
    private static let store: SecureStore = SharedKeychain.store

    private static let schoolHTTP: HTTPClient = SchoolRefreshStack.schoolHTTP()
    private static let showerHTTP: HTTPClient = URLSessionHTTPClient(allowedHosts:AllowedHosts.hotWater)
    private static let laundryHTTP: HTTPClient = URLSessionHTTPClient(allowedHosts:AllowedHosts.laundry)
    /// Settings › 反馈问题: only the feedback host, with a longer resource timeout for screenshots.
    /// nil in a build without the feedback key.
    private static let feedbackHTTP: HTTPClient? = FeedbackReporter.endpoint.map { endpoint in
        URLSessionHTTPClient(allowedHosts:endpoint.allowedHosts, configuration:FeedbackSender.configuration())
    }

    /// The same stack the widget builds for its own reads; the two take turns through the lease.
    private static let schoolStack = SchoolRefreshStack(store:store, http:schoolHTTP, role:"app",
                                                        leaseWait:SchoolRefreshStack.appLeaseWait, leaseFile:RefreshLease.appFile(),
                                                        didWriteSnapshot:{ WidgetCenter.shared.reloadTimelines(ofKind:SharedSnapshotStore.widgetKind) })

    /// The live app's stores and services. The school stack on them is `schoolStack` (one per process).
    @MainActor static let live = CampusServices(
        kind:.live, secureStore:store, defaults:.standard, sharedPreferences:AppIdentity.usableAppGroup.flatMap { UserDefaults(suiteName:$0) },
        schoolHTTP:schoolHTTP, showerHTTP:showerHTTP, laundryHTTP:laundryHTTP, feedbackHTTP:feedbackHTTP,
        showerTransport:BluetoothTransport(), leaseFile:RefreshLease.appFile(),
        applicationSupport:FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask).first,
        sharedDidChange:{ WidgetCenter.shared.reloadAllTimelines() })

    /// The live school stack, for the live `CampusModel` and the background refresh.
    static var liveSchoolStack: SchoolRefreshStack { schoolStack }
    /// The lock around what the app shares with its extensions besides the school session (the
    /// theme): the refresh lease file's, whoever holds the lease.
    static var sharedLock: any SharedLock { schoolStack.refresher.lease ?? UnsharedLock() }
    /// The App Group's preferences, for 重置校日常; nil in a build without the group.
    static var sharedPreferences: AppReset.SharedPreferences? {
        guard let group = AppIdentity.usableAppGroup, let defaults = UserDefaults(suiteName:group) else { return nil }
        return AppReset.SharedPreferences(defaults:defaults, domain:group, lock:sharedLock)
    }

    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "dev"
        return "XiaoRiChang/\(version) (iPhone; iOS \(ProcessInfo.processInfo.operatingSystemVersionString))"
    }
}

/// User-facing text for engine/storage errors not covered by `ServiceError.userMessage`.
enum AppErrorText {
    static func text(_ error: Error) -> String {
        if let e = error as? ServiceError { return e.userMessage }
        if let e = error as? AppReset.InProgress { return e.errorDescription ?? "正在重置" }
        if let e = error as? AppReset.Failure { return e.errorDescription ?? "没完成，稍后再试。" }
        if (error as? ShowerEngineError) == .platformMissing { return ShowerModel.platformMissingText }
        if error is StorageError { return "这台手机的钥匙串暂时写不进去，重启 App 后再试。" }
        return "没完成，稍后再试。"
    }
}
