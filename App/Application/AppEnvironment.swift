import Foundation
import Security
import WidgetKit
import Core

/// Composition root: one Keychain store, one HTTP client per service family, the school session
/// and the snapshot refresher (the only writer of the widget-shared snapshot).
/// The hot-water and laundry engines are built by their models (they depend on the binding / login).
enum AppEnvironment {
    static let store: SecureStore = SharedKeychain.store

    static let schoolHTTP: HTTPClient = SchoolRefreshStack.schoolHTTP()
    static let showerHTTP: HTTPClient = URLSessionHTTPClient(allowedHosts:AllowedHosts.hotWater)
    static let laundryHTTP: HTTPClient = URLSessionHTTPClient(allowedHosts:AllowedHosts.laundry)

    static let schoolVault = StoredSchoolVault(store:store)
    static let showerVault = StoredShowerVault(store:store)
    static let laundryVault = StoredLaundryVault(store:store)
    /// The same stack the widget builds for its own reads; the two take turns through the lease.
    private static let schoolStack = SchoolRefreshStack(store:store, http:schoolHTTP, role:"app",
                                                        leaseWait:SchoolRefreshStack.appLeaseWait, leaseFile:RefreshLease.sharedFile(),
                                                        didWriteSnapshot:{ WidgetCenter.shared.reloadTimelines(ofKind:SharedSnapshotStore.widgetKind) })

    static var school: SchoolSession { schoolStack.session }
    static var refresher: SnapshotRefresher { schoolStack.refresher }

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
        if error is StorageError { return "这台手机的钥匙串暂时写不进去，重启 App 后再试。" }
        return "没完成，稍后再试。"
    }
}
