import Foundation

/// When the Live Activity and the 「还没结束洗澡？」 reminder follow the shower state the engine
/// reports: on every change, and always on the first report of each engine. The state read at
/// launch is the engine's first report too, so comparing alone would skip it, while the lock
/// screen may still show what it showed before the app quit (结算中 for a record now to check).
public struct ShowerSyncGate: Sendable {
    private var synced = false

    public init() {}

    /// Whether to sync for `next`, the state before it being `old`.
    public mutating func shouldSync(_ next: ShowerState, after old: ShowerState) -> Bool {
        defer { synced = true }
        return !synced || next != old
    }

    /// A new engine: its first report syncs again.
    public mutating func reset() { synced = false }
}
