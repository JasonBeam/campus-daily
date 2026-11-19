import Foundation

/// 「正在重置」: written before a reset looks at anything, removed once it cleared everything or
/// found a reason not to. While it is fresh no shower or laundry order may start, in the app or
/// from a shortcut, so nothing new can begin between the reset's check and its clearing. A
/// marker left by a reset that was killed makes the next launch finish that reset; one older
/// than `staleAfter` no longer refuses starts, so a stuck marker never blocks the shower.
public struct ResetMarker: Sendable {
    public static let staleAfter: TimeInterval = 5 * 60
    let store: SecureStore
    private struct Box: Codable { var startedAt: Date }

    public init(store: SecureStore) { self.store = store }

    public func begin(at now: Date) throws { try store.writeJSON(Box(startedAt: now), .sharedResetMarker) }

    public func end() throws { try store.delete(.sharedResetMarker) }

    /// Nil when there is none, or when it can't be read (before the first unlock nothing can
    /// start anyway, and a reset is only resumed from a marker that was read).
    public func startedAt() -> Date? { ((try? store.readJSON(Box.self, .sharedResetMarker)) ?? nil)?.startedAt }

    /// A clock set back counts like one set forward: past `staleAfter` either way, it is stale.
    public func refusesStarts(at now: Date) -> Bool {
        guard let started = startedAt() else { return false }
        return abs(now.timeIntervalSince(started)) < Self.staleAfter
    }

    /// Thrown by every shower and laundry start while a reset runs.
    public func checkStart(at now: Date) throws {
        if refusesStarts(at: now) { throw AppReset.InProgress() }
    }
}
