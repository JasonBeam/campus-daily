//
//  SnapshotStore.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

/// Result of committing a snapshot under an expected `SessionEpoch`.
public struct SnapshotCommitResult: Sendable, Equatable {
    public var snapshot: HomeSnapshot
    public var epoch: SessionEpoch?
    public init(snapshot: HomeSnapshot, epoch: SessionEpoch?) {
        self.snapshot = snapshot
        self.epoch = epoch
    }
}

/// Where the home snapshot is shared with the widget.
public protocol SnapshotStoring: Sendable {
    func loadSnapshot() throws -> HomeSnapshot?
    func saveSnapshot(_ snapshot: HomeSnapshot) throws
    /// Reads the shared `SessionEpoch` (`nil` on fresh install, 0.11.5 upgrade, or mocks without epoch).
    func sessionEpoch() throws -> SessionEpoch?
    /// True when the legacy 0.11.5 `shared.snapshotStale` marker is present.
    func hasLegacyStaleMark() throws -> Bool
    /// Reads or bootstraps the `SessionEpoch` inside the commit lock at the start of a refresh.
    /// On a 0.11.5 upgrade (`shared.sessionEpoch == nil`):
    /// - if legacy `shared.snapshotStale` is present, initializes `(newID, .switching)` (refusing refresh);
    /// - otherwise if `hasCardSession` is true, bootstraps `(newID, .active)` (tagging any legacy snapshot).
    func prepareRefreshEpoch(hasCardSession: Bool) throws -> SessionEpoch?
    /// Replaces a stale/pending-clear snapshot with an empty snapshot tagged with the epoch id
    /// and advances the epoch phase (`.activePendingClear` -> `.active`,
    /// `.signedOutPendingClear` -> `.signedOut`), recovers `.switching` by deleting all residual
    /// credentials before transitioning to `.signedOut` (or `.signedOutPendingClear`), or
    /// conservatively migrates a legacy 0.11.5 `shared.snapshotStale` through `.switching`.
    /// Called inside the commit lock.
    func finishPendingClear() throws
    /// Atomically verifies `expectedEpoch`, tags `snapshot.epochID`, saves `shared.snapshot`,
    /// and advances `.activePendingClear` -> `.active` (or bootstraps an `.active` epoch on
    /// 0.11.5 upgrade). Returns `nil` when rejected due to epoch mismatch or non-committable phase.
    func commitSnapshot(_ snapshot: HomeSnapshot, expectedEpoch: SessionEpoch?) throws -> SnapshotCommitResult?
    /// Clears `shared.snapshot` to an empty snapshot tagged with the current epoch id and
    /// advances `.activePendingClear` -> `.active` or `.signedOutPendingClear` -> `.signedOut`.
    /// Leaves `.switching` unchanged so `finishPendingClear` still cleans up residual credentials.
    /// Called inside the commit lock.
    func clearSnapshot() throws
}

public extension SnapshotStoring {
    func sessionEpoch() throws -> SessionEpoch? { nil }
    func hasLegacyStaleMark() throws -> Bool { false }
    func prepareRefreshEpoch(hasCardSession: Bool) throws -> SessionEpoch? { try sessionEpoch() }
    func finishPendingClear() throws {}
    func commitSnapshot(_ snapshot: HomeSnapshot, expectedEpoch: SessionEpoch?) throws -> SnapshotCommitResult? {
        try saveSnapshot(snapshot)
        return SnapshotCommitResult(snapshot: snapshot, epoch: expectedEpoch)
    }
    func clearSnapshot() throws {
        try saveSnapshot(.empty)
    }
}

/// The widget-shared home snapshot (`shared.snapshot`, ≤ 64 KiB JSON), guarded by `SessionEpoch`.
///
/// Epoch rules:
/// - When `shared.sessionEpoch` exists:
///   - Readable ONLY when `epoch.phase == .active` AND `snapshot.epochID == epoch.id`.
///   - In `.switching`, `.activePendingClear`, `.signedOutPendingClear`, `.signedOut`,
///     `loadSnapshot()` returns `nil`.
/// - When `shared.sessionEpoch` is absent (fresh install or 0.11.5 upgrade):
///   - If legacy `shared.snapshotStale` is present, `loadSnapshot()` returns `nil`.
///   - Otherwise a legacy snapshot (`epochID == nil`) is readable until the next write/migration
///     bootstraps a `SessionEpoch`.
/// - Never writes `shared.snapshotStale`; deletes any leftover legacy mark after a successful clear/write.
public struct SharedSnapshotStore: SnapshotStoring {
    let store: SecureStore
    /// Called after each successful write (App: `WidgetCenter.reloadTimelines(ofKind:)`).
    let didWrite: @Sendable () -> Void
    /// Diagnostic events (event name and storage status only, never values).
    let diagnostic: @Sendable (String) -> Void

    public static let widgetKind = "XiaoRiChangBalances"

    /// Credential keys removed during `.switching` recovery (never includes `schoolDevice`).
    private static let switchingCredentialKeys: [StoreKey] = [
        .schoolPassword, .schoolPortal, .schoolEcykt, .schoolProfile,
    ]

    public init(store: SecureStore, didWrite: @escaping @Sendable () -> Void = {},
                diagnostic: @escaping @Sendable (String) -> Void = { _ in }) {
        self.store = store
        self.didWrite = didWrite
        self.diagnostic = diagnostic
    }

    private var epochStore: SessionEpochStore { SessionEpochStore(store: store) }

    public func sessionEpoch() throws -> SessionEpoch? {
        try epochStore.read()
    }

    public func hasLegacyStaleMark() throws -> Bool {
        try epochStore.hasLegacyStaleMark()
    }

    public func prepareRefreshEpoch(hasCardSession: Bool) throws -> SessionEpoch? {
        if let current = try epochStore.read() {
            return current
        }
        // 0.11.5 upgrade with legacy `shared.snapshotStale`: conservatively enter `.switching`
        // so the refresh stops without touching the network or legacy data.
        if try epochStore.hasLegacyStaleMark() {
            let switching = SessionEpoch(phase: .switching)
            try epochStore.write(switching)
            return switching
        }
        // Fresh install or clean 0.11.5 upgrade (`shared.sessionEpoch == nil`): defer epoch
        // bootstrapping until `commitSnapshot` writes a non-empty snapshot, so a timed-out,
        // cancelled, or older reading never mutates Keychain.
        return nil
    }

    public func loadSnapshot() throws -> HomeSnapshot? {
        if let epoch = try epochStore.read() {
            guard epoch.allowsSnapshotRead else { return nil }
            guard let snapshot = try store.readJSON(HomeSnapshot.self, .sharedSnapshot) else { return nil }
            guard snapshot.epochID == epoch.id else { return nil }
            return snapshot
        }
        // Fresh install or 0.11.5 upgrade (no `shared.sessionEpoch` yet).
        guard try !epochStore.hasLegacyStaleMark() else { return nil }
        guard let snapshot = try store.readJSON(HomeSnapshot.self, .sharedSnapshot) else { return nil }
        // Fail closed if a tagged snapshot exists without its epoch record.
        guard snapshot.epochID == nil else { return nil }
        return snapshot
    }

    public func saveSnapshot(_ snapshot: HomeSnapshot) throws {
        try writeRawSnapshot(snapshot)
        dropLegacyStaleMarkIfPresent()
        didWrite()
    }

    public func commitSnapshot(_ snapshot: HomeSnapshot, expectedEpoch: SessionEpoch?) throws -> SnapshotCommitResult? {
        let current = try epochStore.read()
        if let expected = expectedEpoch {
            guard let current, current.id == expected.id, current.allowsRefreshCommit else { return nil }
            var tagged = snapshot
            tagged.epochID = current.id
            try writeRawSnapshot(tagged)
            var finalEpoch = current
            if current.phase == .activePendingClear {
                finalEpoch = SessionEpoch(id: current.id, phase: .active)
                try epochStore.write(finalEpoch)
            }
            dropLegacyStaleMarkIfPresent()
            didWrite()
            return SnapshotCommitResult(snapshot: tagged, epoch: finalEpoch)
        }
        // Upgrade / no-epoch path: reject if another process created an epoch or legacy stale mark meanwhile.
        guard current == nil, try !epochStore.hasLegacyStaleMark() else { return nil }
        if snapshot.isEmpty {
            try writeRawSnapshot(.empty)
            dropLegacyStaleMarkIfPresent()
            didWrite()
            return SnapshotCommitResult(snapshot: .empty, epoch: nil)
        }
        let bootstrapped = SessionEpoch(phase: .active)
        var tagged = snapshot
        tagged.epochID = bootstrapped.id
        try writeRawSnapshot(tagged)
        try epochStore.write(bootstrapped)
        dropLegacyStaleMarkIfPresent()
        didWrite()
        return SnapshotCommitResult(snapshot: tagged, epoch: bootstrapped)
    }

    public func clearSnapshot() throws {
        let current = try epochStore.read()
        let cleared = HomeSnapshot(epochID: current?.id)
        try writeRawSnapshot(cleared)
        if let current, current.needsPendingClear {
            try epochStore.write(SessionEpoch(id: current.id, phase: current.clearedPhase))
        }
        dropLegacyStaleMarkIfPresent()
        didWrite()
    }

    public func finishPendingClear() throws {
        if let current = try epochStore.read() {
            switch current.phase {
            case .switching:
                try recoverSwitching(epochID: current.id)
                return
            case .activePendingClear, .signedOutPendingClear:
                try writeRawSnapshot(HomeSnapshot(epochID: current.id))
                try epochStore.write(SessionEpoch(id: current.id, phase: current.clearedPhase))
                dropLegacyStaleMarkIfPresent()
                didWrite()
                return
            case .active, .signedOut:
                dropLegacyStaleMarkIfPresent()
                return
            }
        }
        // 0.11.5 upgrade with legacy `shared.snapshotStale` present: conservatively initialize
        // `(newID, .switching)` and run full `.switching` recovery cleanup to `.signedOut`.
        guard try epochStore.hasLegacyStaleMark() else { return }
        let switching = SessionEpoch(phase: .switching)
        try epochStore.write(switching)
        try recoverSwitching(epochID: switching.id)
    }

    /// Cleans up an interrupted `.switching` epoch: deletes all residual credentials, then writes
    /// an empty snapshot tagged with `epochID` and transitions to `.signedOut` (or
    /// `.signedOutPendingClear` if the snapshot write fails). Never activates a session.
    private func recoverSwitching(epochID: String) throws {
        var firstError: Error?
        for key in Self.switchingCredentialKeys {
            do { try store.delete(key) } catch { firstError = firstError ?? error }
        }
        if let firstError {
            // Keep `(epochID, .switching)` so the next `finishPendingClear` retries deletion.
            throw firstError
        }
        do {
            try writeRawSnapshot(HomeSnapshot(epochID: epochID))
        } catch {
            // All credentials are gone; advance to `.signedOutPendingClear` so the next retry
            // only needs to overwrite `shared.snapshot`.
            try? epochStore.write(SessionEpoch(id: epochID, phase: .signedOutPendingClear))
            throw error
        }
        try epochStore.write(SessionEpoch(id: epochID, phase: .signedOut))
        dropLegacyStaleMarkIfPresent()
        didWrite()
    }

    private func writeRawSnapshot(_ snapshot: HomeSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let data: Data
        do { data = try encoder.encode(snapshot) }
        catch { throw StorageError(operation: "encode shared.snapshot", status: -1) }
        guard data.count <= HomeSnapshot.maxEncodedBytes else {
            throw StorageError(operation: "write shared.snapshot (too large)", status: -1)
        }
        try store.write(data, for: .sharedSnapshot)
    }

    /// Best-effort removal of legacy 0.11.5 `shared.snapshotStale` after a write succeeded.
    private func dropLegacyStaleMarkIfPresent() {
        let marked: Bool
        do { marked = try epochStore.hasLegacyStaleMark() } catch { marked = true }
        guard marked else { return }
        do { try epochStore.deleteLegacyStaleMark() } catch {
            diagnostic("snapshot.staleClearFailed" + ((error as? StorageError).map { " status=\($0.status)" } ?? ""))
        }
    }
}
