import Foundation

/// Where the home snapshot is shared with the widget.
public protocol SnapshotStoring: Sendable {
    func loadSnapshot() throws -> HomeSnapshot?
    func saveSnapshot(_ snapshot: HomeSnapshot) throws
    /// A snapshot marked stale is replaced by the empty one and the mark dropped; nothing
    /// happens without a mark. Called inside the lease file's lock (`SnapshotRefresher`).
    func finishPendingClear() throws
}

public extension SnapshotStoring {
    func finishPendingClear() throws {}
}

/// The widget-shared home snapshot (`shared.snapshot`, ≤ 64 KiB JSON).
///
/// While `shared.snapshotStale` is there (someone else signed in, or a sign-out, and the
/// previous person's numbers may still be stored), the snapshot reads as absent, here and so for
/// every reader (the app, a relaunch, the widget). The mark is only looked for, never decoded,
/// and one that can't be read hides too (the read throws). A write that goes through drops it:
/// whatever was written was reduced from what this store read, which was nothing while marked.
public struct SharedSnapshotStore: SnapshotStoring {
    let store: SecureStore
    /// Called after each successful write (App: `WidgetCenter.reloadTimelines(ofKind:)`).
    let didWrite: @Sendable () -> Void
    /// A mark that could not be dropped (the event name and status only).
    let diagnostic: @Sendable (String) -> Void

    public static let widgetKind = "XiaoRiChangBalances"

    public init(store: SecureStore, didWrite: @escaping @Sendable () -> Void = {},
                diagnostic: @escaping @Sendable (String) -> Void = { _ in }) {
        self.store = store
        self.didWrite = didWrite
        self.diagnostic = diagnostic
    }

    public func loadSnapshot() throws -> HomeSnapshot? {
        guard try store.read(.sharedSnapshotStale) == nil else { return nil }
        return try store.readJSON(HomeSnapshot.self, .sharedSnapshot)
    }

    public func saveSnapshot(_ snapshot: HomeSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let data: Data
        do { data = try encoder.encode(snapshot) }
        catch { throw StorageError(operation: "encode shared.snapshot", status: -1) }
        guard data.count <= HomeSnapshot.maxEncodedBytes else {
            throw StorageError(operation: "write shared.snapshot (too large)", status: -1)
        }
        try store.write(data, for: .sharedSnapshot)
        dropStaleMark()
        didWrite()
    }

    public func finishPendingClear() throws {
        guard try store.read(.sharedSnapshotStale) != nil else { return }
        try saveSnapshot(.empty)
    }

    /// After a write that went through. A mark that can't be dropped stays: the snapshot is
    /// hidden until the next write tries again.
    private func dropStaleMark() {
        // A mark that can't be read may be there: deleting is tried all the same.
        let marked: Bool
        do { marked = try store.read(.sharedSnapshotStale) != nil } catch { marked = true }
        guard marked else { return }
        do { try store.delete(.sharedSnapshotStale) } catch {
            diagnostic("snapshot.staleClearFailed" + ((error as? StorageError).map { " status=\($0.status)" } ?? ""))
        }
    }
}
