import Foundation
import Core

/// An in-memory Keychain whose reads, writes and deletions fail one key at a time (as the
/// Keychain refuses one item, a full or locked one), and which keeps the order of its writes
/// and deletions. Reads fail with `errSecInteractionNotAllowed`, writes and deletions with a
/// Keychain status too (never -1, which callers read as "doesn't decode").
public final class KeyedFailureStore: SecureStore, @unchecked Sendable {
    // @unchecked: every field is touched only under `lock`.
    private let lock = NSLock()
    private var items: [StoreKey: Data] = [:]
    private var reads: Set<StoreKey> = []
    private var writes: Set<StoreKey> = []
    private var deletes: Set<StoreKey> = []
    private var log: [String] = []

    public init() {}

    public var refusingReads: Set<StoreKey> {
        get { lock.withLock { reads } }
        set { lock.withLock { reads = newValue } }
    }
    public var refusingWrites: Set<StoreKey> {
        get { lock.withLock { writes } }
        set { lock.withLock { writes = newValue } }
    }
    public var refusingDeletes: Set<StoreKey> {
        get { lock.withLock { deletes } }
        set { lock.withLock { deletes = newValue } }
    }
    /// "write <key>" / "delete <key>" for each one that went through, in order.
    public var steps: [String] { lock.withLock { log } }
    public func forgetSteps() { lock.withLock { log = [] } }

    public func read(_ key: StoreKey) throws -> Data? {
        try lock.withLock {
            if reads.contains(key) { throw StorageError(operation: "read \(key.rawValue)", status: -25308) }
            return items[key]
        }
    }

    public func write(_ data: Data, for key: StoreKey) throws {
        try lock.withLock {
            if writes.contains(key) { throw StorageError(operation: "write \(key.rawValue)", status: -25308) }
            items[key] = data
            log.append("write " + key.rawValue)
        }
    }

    public func delete(_ key: StoreKey) throws {
        try lock.withLock {
            if deletes.contains(key) { throw StorageError(operation: "delete \(key.rawValue)", status: -25308) }
            if items.removeValue(forKey: key) != nil { log.append("delete " + key.rawValue) }
        }
    }
}
