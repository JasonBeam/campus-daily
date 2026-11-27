//
//  SchoolRefreshStack.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

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
    /// The widget's wait for the lease file's lock before it finishes a pending clear: short,
    /// it comes before the read's own wait (`widgetLeaseWait`).
    public static let widgetPendingClearWait: TimeInterval = 0.5

    /// `leaseFile`: `RefreshLease.appFile()` in the app, `RefreshLease.sharedFile()` in the
    /// widget. Always creates a `RefreshLease`: when `leaseFile` is `nil`, the lease is
    /// unavailable and fails closed across refresh, login commits, and locked writes.
    public init(store: SecureStore, http: HTTPClient, role: String, leaseWait: TimeInterval, leaseFile: LeaseFile?,
                didWriteSnapshot: @escaping @Sendable () -> Void = {},
                diagnostic: @escaping @Sendable (String) -> Void = SnapshotRefresher.osLog,
                debugLog: any DebugLogSink = NoDebugLog()) {
        let lease = RefreshLease(file: leaseFile, owner: RefreshLease.owner(role))
        session = SchoolSession(portal: PortalClient(http: http), ecykt: EcyktClient(http: http),
                                vault: StoredSchoolVault(store: store), passwordLogin: CASLoginClient(http: http),
                                diagnostic: diagnostic,
                                createsLoginDeviceID: role != "widget", debugLog: debugLog,
                                profileLock: lease)
        refresher = SnapshotRefresher(school: session, store: SharedSnapshotStore(store: store, didWrite: didWriteSnapshot,
                                                                                  diagnostic: diagnostic),
                                      lease: lease,
                                      leaseWait: leaseWait, diagnostic: diagnostic)
    }

    /// In-memory stack for sample mode and tests without an on-disk lease file.
    public static func inMemory(store: SecureStore, http: HTTPClient, role: String = "app",
                                didWriteSnapshot: @escaping @Sendable () -> Void = {},
                                diagnostic: @escaping @Sendable (String) -> Void = { _ in },
                                debugLog: any DebugLogSink = NoDebugLog(),
                                lock: InMemoryCommitLock = InMemoryCommitLock()) -> SchoolRefreshStack {
        let session = SchoolSession(portal: PortalClient(http: http), ecykt: EcyktClient(http: http),
                                    vault: StoredSchoolVault(store: store), passwordLogin: CASLoginClient(http: http),
                                    diagnostic: diagnostic,
                                    createsLoginDeviceID: role != "widget", debugLog: debugLog,
                                    profileLock: lock)
        let refresher = SnapshotRefresher(school: session,
                                          store: SharedSnapshotStore(store: store, didWrite: didWriteSnapshot,
                                                                     diagnostic: diagnostic),
                                          diagnostic: diagnostic,
                                          inMemoryLock: lock)
        return SchoolRefreshStack(session: session, refresher: refresher)
    }

    private init(session: SchoolSession, refresher: SnapshotRefresher) {
        self.session = session
        self.refresher = refresher
    }

    /// The URLSession client for the school hosts only.
    /// `log`: where each request line goes (the app passes its TestFlight log's `DebugHTTPLogSink`).
    public static func schoolHTTP(log: HTTPLogSink = OSLogSink()) -> HTTPClient {
        URLSessionHTTPClient(allowedHosts: AllowedHosts.school, log: log)
    }
}

/// What the widget's timeline provider does before drawing, kept here so it is tested.
public enum WidgetRefresh {
    /// Runs one refresh unless `WidgetStatus.shouldRefresh` says the stored snapshot is recent
    /// enough, giving up after `deadline`: then the read is cancelled (it writes nothing) and
    /// the stored snapshot is returned at once, without waiting for the cancelled read to wind
    /// down. Returns the snapshot to draw.
    public static func run(_ refresher: SnapshotRefresher, now: Date, deadline: TimeInterval,
                           expectedEpochID: String? = nil) async -> HomeSnapshot {
        let stored = refresher.latest()
        guard WidgetStatus.shouldRefresh(snapshot: stored, now: now) else { return stored }
        let result = await withCheckedContinuation { continuation in
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
        if let expectedEpochID, !result.isEmpty, result.epochID != expectedEpochID {
            return .empty
        }
        return result
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
