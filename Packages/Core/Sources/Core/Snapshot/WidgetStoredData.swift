import Foundation

/// What the widget draws from: the shared snapshot and the saved account, read together.
/// Before the first unlock after a restart (or when the Keychain refuses a read) nothing can be
/// read; that is not the same as nobody being signed in, and the widget must not draw the
/// signed-out face for it.
public struct WidgetStoredData: Sendable, Equatable {
    public var snapshot: HomeSnapshot?
    public var account: SchoolAccount?

    /// How soon the widget asks again after a read it couldn't do.
    public static let unreadableRetry: TimeInterval = 5 * 60

    public init(snapshot: HomeSnapshot?, account: SchoolAccount?) {
        self.snapshot = snapshot; self.account = account
    }

    /// Nil = the Keychain could not be read now. An item that is there but can't be decoded
    /// (written by a newer build, damaged) counts as absent, so it can't block the widget forever.
    public static func read(snapshots: SnapshotStoring, vault: SchoolVault) -> WidgetStoredData? {
        do {
            return WidgetStoredData(snapshot: try readable { try snapshots.loadSnapshot() },
                                    account: try readable { try vault.account() })
        } catch {
            return nil
        }
    }

    /// Rethrows only Keychain failures; a decoding failure becomes nil.
    private static func readable<T>(_ read: () throws -> T?) throws -> T? {
        do { return try read() } catch let e as StorageError where e.status == -1 { return nil }
    }
}
