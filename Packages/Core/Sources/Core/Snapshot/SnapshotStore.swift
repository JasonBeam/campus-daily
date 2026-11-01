import Foundation

/// Where the home snapshot is shared with the widget.
public protocol SnapshotStoring: Sendable {
    func loadSnapshot() throws -> HomeSnapshot?
    func saveSnapshot(_ snapshot: HomeSnapshot) throws
}

/// The widget-shared home snapshot (`shared.snapshot`, ≤ 64 KiB JSON).
public struct SharedSnapshotStore: SnapshotStoring {
    let store: SecureStore
    /// Called after each successful write (App: `WidgetCenter.reloadTimelines(ofKind:)`).
    let didWrite: @Sendable () -> Void

    public static let widgetKind = "XiaoRiChangBalances"

    public init(store: SecureStore, didWrite: @escaping @Sendable () -> Void = {}) {
        self.store = store
        self.didWrite = didWrite
    }

    public func loadSnapshot() throws -> HomeSnapshot? {
        try store.readJSON(HomeSnapshot.self, .sharedSnapshot)
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
        didWrite()
    }
}
