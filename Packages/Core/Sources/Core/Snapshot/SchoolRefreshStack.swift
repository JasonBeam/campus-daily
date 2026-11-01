import Foundation

/// The school session and the snapshot refresher, built the same way in the app and in the
/// widget so both run one refresh ladder and one write path. Each process builds this once;
/// `role` ("app" / "widget") names its lease owner; only the app may create the login device id.
public struct SchoolRefreshStack: Sendable {
    public let session: SchoolSession
    public let refresher: SnapshotRefresher

    /// The app waits longer for the widget's read than the widget waits for the app's: the
    /// widget has only a few seconds before it must draw.
    public static let appLeaseWait: TimeInterval = 15
    public static let widgetLeaseWait: TimeInterval = 5

    /// `leaseFile`: `RefreshLease.sharedFile()` in the app and the widget. Without it (signed
    /// without the App Group) the app refreshes on its own and the widget never does, so the
    /// two never read at the same time. Builds before the lease file kept the lease in the
    /// Keychain; that leftover item is deleted here.
    public init(store: SecureStore, http: HTTPClient, role: String, leaseWait: TimeInterval, leaseFile: LeaseFile?,
                didWriteSnapshot: @escaping @Sendable () -> Void = {},
                diagnostic: @escaping @Sendable (String) -> Void = SnapshotRefresher.osLog) {
        session = SchoolSession(portal: PortalClient(http: http), ecykt: EcyktClient(http: http),
                                vault: StoredSchoolVault(store: store), passwordLogin: CASLoginClient(http: http),
                                diagnostic: diagnostic, credentialLog: CredentialLifetimeLog(store: store),
                                createsLoginDeviceID: role != "widget")
        try? store.delete(.sharedRefreshLease)
        let lease: RefreshLease? = leaseFile == nil && role != "widget" ? nil : RefreshLease(file: leaseFile, owner: RefreshLease.owner(role))
        refresher = SnapshotRefresher(school: session, store: SharedSnapshotStore(store: store, didWrite: didWriteSnapshot),
                                      lease: lease,
                                      leaseWait: leaseWait, diagnostic: diagnostic)
    }

    /// The URLSession client for the school hosts only.
    public static func schoolHTTP() -> HTTPClient { URLSessionHTTPClient(allowedHosts: AllowedHosts.school) }
}

/// What the widget's timeline provider does before drawing, kept here so it is tested.
public enum WidgetRefresh {
    /// Runs one refresh unless `WidgetStatus.shouldRefresh` says the stored snapshot is recent
    /// enough, giving up after `deadline`: then the read is cancelled (it writes nothing) and
    /// the stored snapshot is returned at once, without waiting for the cancelled read to wind
    /// down. Returns the snapshot to draw.
    public static func run(_ refresher: SnapshotRefresher, now: Date, deadline: TimeInterval) async -> HomeSnapshot {
        let stored = refresher.latest()
        guard WidgetStatus.shouldRefresh(snapshot: stored, now: now) else { return stored }
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let read = Task {
                let snapshot = await refresher.refresh(inBackground: true).snapshot
                once.resume(snapshot)
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, deadline) * 1_000_000_000))
                read.cancel()
                once.resume(refresher.latest())
            }
        }
    }

    /// Resumes the continuation with the first answer only.
    private final class Once: @unchecked Sendable {
        // @unchecked: `continuation` is touched only under `lock`.
        private let lock = NSLock()
        private var continuation: CheckedContinuation<HomeSnapshot, Never>?
        init(_ c: CheckedContinuation<HomeSnapshot, Never>) { continuation = c }
        func resume(_ value: HomeSnapshot) {
            let c: CheckedContinuation<HomeSnapshot, Never>? = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            c?.resume(returning: value)
        }
    }
}
