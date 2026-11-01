import Foundation
#if canImport(Security)
import Security
#endif

/// The SecItem calls, behind a protocol so the access-group fallback is testable without
/// touching the host Keychain. Status codes are `OSStatus` values.
public protocol KeychainBackend: Sendable {
    func copy(service: String, account: String, accessGroup: String?) -> (status: Int32, data: Data?)
    func add(service: String, account: String, accessGroup: String?, accessibility: StoreKey.Accessibility, data: Data) -> Int32
    func update(service: String, account: String, accessGroup: String?, accessibility: StoreKey.Accessibility, data: Data) -> Int32
    func delete(service: String, account: String, accessGroup: String?) -> Int32
}

public enum KeychainStatus {
    public static let success: Int32 = 0             // errSecSuccess
    public static let itemNotFound: Int32 = -25300   // errSecItemNotFound
    public static let duplicateItem: Int32 = -25299  // errSecDuplicateItem
    public static let missingEntitlement: Int32 = -34018 // errSecMissingEntitlement
}

/// Keychain store with two access groups: the shared group the widget can read, for keys whose
/// `isShared` is true, and the app's private group for everything else.
///
/// Re-signed IPAs may lose the `keychain-access-groups` entitlement. When a write with a group
/// fails with `errSecMissingEntitlement`, the store falls back to **no access group** (the
/// default group) for that group and remembers it for later reads/writes; the widget then simply
/// has no data, and the app keeps working. Any other write failure (a locked device, say) is
/// thrown and changes nothing for later writes.
///
/// An item can sit in the other group from where its key now belongs: builds before the private
/// group existed wrote everything into the shared group, and builds before the widget refreshed
/// by itself kept the portal token and login device id in the private group. Such an item is
/// moved: written to its group, read back, and only then deleted from the old one. Any failed
/// step leaves the old copy as it was, so nobody is signed out; the move is retried on the next
/// read or `migrateItemGroups()`.
public final class KeychainSecureStore: SecureStore, @unchecked Sendable {
    // @unchecked: mutable state guarded by `lock`.
    private let backend: KeychainBackend
    private let groups: @Sendable () -> (shared: String?, private: String?)
    private let lock = NSLock()
    private var unavailable: Set<String> = []

    /// `accessGroup`: the resolved `<TeamPrefix>.com.beamjason.xiaorichang.shared`, or nil.
    /// `privateGroup`: the resolved app-only group, or nil (the widget, or unknown): private items
    /// then use the default group.
    public init(backend: KeychainBackend, accessGroup: String?, privateGroup: String? = nil) {
        self.backend = backend
        let resolved = (shared: accessGroup, private: privateGroup == accessGroup ? nil : privateGroup)
        self.groups = { resolved }
    }

    /// Groups resolved on each use from `probe`, so a probe that failed early (before the first
    /// unlock) is retried instead of fixing the groups for the whole process.
    public init(backend: KeychainBackend, groups probe: KeychainGroupProbe) {
        self.backend = backend
        self.groups = {
            let shared = probe.sharedGroup, own = probe.privateGroup
            return (shared, own == shared ? nil : own)
        }
    }

    private var sharedGroup: String? { groups().shared }
    private var privateGroup: String? { groups().private }

    /// True once a shared-group write failed and the store switched to no access group.
    public var isUsingFallback: Bool { lock.withLock { sharedGroup.map(unavailable.contains) ?? false } }

    private func usable(_ group: String?) -> String? {
        guard let group else { return nil }
        return lock.withLock { unavailable.contains(group) } ? nil : group
    }

    private func group(for key: StoreKey) -> String? {
        usable(key.isShared ? sharedGroup : privateGroup)
    }

    /// The other group, where an older build may have left this key: the shared group for a
    /// private key, the private group for a shared one. Nil without both groups (the widget has
    /// no private group, so it never moves anything).
    private func legacyGroup(for key: StoreKey) -> String? {
        guard let privateGroup, let sharedGroup, usable(privateGroup) != nil, usable(sharedGroup) != nil else { return nil }
        return key.isShared ? privateGroup : sharedGroup
    }

    public func read(_ key: StoreKey) throws -> Data? {
        let group = group(for: key)
        var r = backend.copy(service: key.service, account: StoreKey.account, accessGroup: group)
        if group != nil, r.status == KeychainStatus.itemNotFound || r.status == KeychainStatus.missingEntitlement {
            if let legacy = legacyGroup(for: key) {
                let old = backend.copy(service: key.service, account: StoreKey.account, accessGroup: legacy)
                if old.status == KeychainStatus.success, let data = old.data {
                    _ = move(key, data)
                    return data
                }
            }
            // An earlier fallback write may have stored it without the group.
            r = backend.copy(service: key.service, account: StoreKey.account, accessGroup: nil)
        }
        switch r.status {
        case KeychainStatus.success: return r.data
        case KeychainStatus.itemNotFound: return nil
        default: throw StorageError(operation: "read \(key.rawValue)", status: r.status)
        }
    }

    public func write(_ data: Data, for key: StoreKey) throws {
        if let group = group(for: key) {
            let status = upsert(key, data, group)
            if status == KeychainStatus.success { return }
            guard status == KeychainStatus.missingEntitlement else {
                throw StorageError(operation: "write \(key.rawValue)", status: status)
            }
            lock.withLock { _ = unavailable.insert(group) }
        }
        let status = upsert(key, data, nil)
        guard status == KeychainStatus.success else { throw StorageError(operation: "write \(key.rawValue)", status: status) }
    }

    /// `SecItemAdd` alone: it fails with `errSecDuplicateItem` when the item exists, which the
    /// Keychain decides atomically for every process sharing the group.
    public func create(_ data: Data, for key: StoreKey) throws -> Bool {
        var group = group(for: key)
        var status = backend.add(service: key.service, account: StoreKey.account, accessGroup: group,
                                 accessibility: key.accessibility, data: data)
        if status == KeychainStatus.missingEntitlement, let missing = group {
            lock.withLock { _ = unavailable.insert(missing) }
            group = nil
            status = backend.add(service: key.service, account: StoreKey.account, accessGroup: nil,
                                 accessibility: key.accessibility, data: data)
        }
        if status == KeychainStatus.duplicateItem { return false }
        guard status == KeychainStatus.success else { throw StorageError(operation: "create \(key.rawValue)", status: status) }
        return true
    }

    /// `SecItemUpdate` alone: it never adds, so an item deleted by another process stays deleted.
    /// Tried in the key's group, then without a group (where a fallback create may have put it).
    public func replace(_ data: Data, for key: StoreKey) throws -> Bool {
        let group = group(for: key)
        for g in group == nil ? [nil] : [group, nil] {
            let status = backend.update(service: key.service, account: StoreKey.account, accessGroup: g,
                                        accessibility: key.accessibility, data: data)
            if status == KeychainStatus.success { return true }
            guard status == KeychainStatus.itemNotFound || status == KeychainStatus.missingEntitlement else {
                throw StorageError(operation: "replace \(key.rawValue)", status: status)
            }
        }
        return false
    }

    public func delete(_ key: StoreKey) throws {
        var statuses = [backend.delete(service: key.service, account: StoreKey.account, accessGroup: nil)]
        for group in [sharedGroup, privateGroup].compactMap({ $0 }) {
            statuses.append(backend.delete(service: key.service, account: StoreKey.account, accessGroup: group))
        }
        if let bad = statuses.first(where: { $0 != KeychainStatus.success && $0 != KeychainStatus.itemNotFound && $0 != KeychainStatus.missingEntitlement }) {
            throw StorageError(operation: "delete \(key.rawValue)", status: bad)
        }
    }

    /// Moves every item still in its old group into the group its key belongs to. Returns the
    /// keys still in their old group (a step failed; retried next time).
    @discardableResult
    public func migrateItemGroups() -> [StoreKey] {
        StoreKey.allCases.filter { key in
            guard let legacy = legacyGroup(for: key) else { return false }
            let old = backend.copy(service: key.service, account: StoreKey.account, accessGroup: legacy)
            if old.status == KeychainStatus.itemNotFound { return false }
            guard old.status == KeychainStatus.success, let data = old.data else { return true }
            return !move(key, data)
        }
    }

    /// New copy first; the old copy goes only once the new one reads back the same. A copy
    /// already in the new group is newer (this build writes nowhere else), so it is kept.
    /// A failed read-back deletes nothing: the new copy may already be a newer value written
    /// meanwhile, and a leftover copy of the old value is harmless (the next run compares
    /// against it and finishes the move). The new copy gets the key's accessibility today.
    private func move(_ key: StoreKey, _ legacyData: Data) -> Bool {
        guard let target = group(for: key), let source = legacyGroup(for: key) else { return false }
        let existing = backend.copy(service: key.service, account: StoreKey.account, accessGroup: target)
        let expected: Data
        switch existing.status {
        case KeychainStatus.success:
            guard let data = existing.data else { return false }
            expected = data
        case KeychainStatus.itemNotFound:
            let added = backend.add(service: key.service, account: StoreKey.account, accessGroup: target,
                                    accessibility: key.accessibility, data: legacyData)
            guard added == KeychainStatus.success else { return false }
            expected = legacyData
        default:
            return false
        }
        let back = backend.copy(service: key.service, account: StoreKey.account, accessGroup: target)
        guard back.status == KeychainStatus.success, back.data == expected else { return false }
        return backend.delete(service: key.service, account: StoreKey.account, accessGroup: source) == KeychainStatus.success
    }

    private func upsert(_ key: StoreKey, _ data: Data, _ group: String?) -> Int32 {
        let status = backend.add(service: key.service, account: StoreKey.account, accessGroup: group,
                                 accessibility: key.accessibility, data: data)
        guard status == KeychainStatus.duplicateItem else { return status }
        return backend.update(service: key.service, account: StoreKey.account, accessGroup: group,
                              accessibility: key.accessibility, data: data)
    }
}

#if canImport(Security)
/// The real SecItem backend (generic passwords). Not used by `swift test`.
public struct SecItemKeychainBackend: KeychainBackend {
    public init() {}

    private func base(_ service: String, _ account: String, _ group: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    private func accessible(_ a: StoreKey.Accessibility) -> CFString {
        switch a {
        case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }

    public func copy(service: String, account: String, accessGroup: String?) -> (status: Int32, data: Data?) {
        var q = base(service, account, accessGroup)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        return (status, out as? Data)
    }

    public func add(service: String, account: String, accessGroup: String?, accessibility: StoreKey.Accessibility, data: Data) -> Int32 {
        var q = base(service, account, accessGroup)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = accessible(accessibility)
        return SecItemAdd(q as CFDictionary, nil)
    }

    public func update(service: String, account: String, accessGroup: String?, accessibility: StoreKey.Accessibility, data: Data) -> Int32 {
        let q = base(service, account, accessGroup)
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: accessible(accessibility)]
        return SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
    }

    public func delete(service: String, account: String, accessGroup: String?) -> Int32 {
        SecItemDelete(base(service, account, accessGroup) as CFDictionary)
    }
}
#endif

/// In-memory store for tests and previews, with injectable write and read failures.
public final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [StoreKey: Data] = [:]
    private var failing: Set<StoreKey> = []
    private var unreadable = false
    private var afterWrite: [StoreKey: @Sendable () -> Void] = [:]
    private var beforeWrite: [StoreKey: @Sendable () -> Void] = [:]

    public init() {}

    /// Runs `step` once, right after the next write to `key` (as another process would act next).
    public func onNextWrite(to key: StoreKey, _ step: @escaping @Sendable () -> Void) {
        lock.withLock { afterWrite[key] = step }
    }

    /// Runs `step` once, right before the next write to `key`.
    public func beforeNextWrite(to key: StoreKey, _ step: @escaping @Sendable () -> Void) {
        lock.withLock { beforeWrite[key] = step }
    }

    /// Every read fails as the Keychain does before the first unlock (`errSecInteractionNotAllowed`).
    public func failReads(_ fail: Bool = true) { lock.withLock { unreadable = fail } }

    public func failWrites(to key: StoreKey, _ fail: Bool = true) {
        lock.withLock { if fail { failing.insert(key) } else { failing.remove(key) } }
    }

    public func read(_ key: StoreKey) throws -> Data? {
        try lock.withLock {
            if unreadable { throw StorageError(operation: "read \(key.rawValue)", status: -25308) }
            return items[key]
        }
    }

    public func write(_ data: Data, for key: StoreKey) throws {
        lock.withLock { beforeWrite.removeValue(forKey: key) }?()
        let step = try lock.withLock { () -> (@Sendable () -> Void)? in
            if failing.contains(key) { throw StorageError(operation: "write \(key.rawValue)", status: -1) }
            items[key] = data
            return afterWrite.removeValue(forKey: key)
        }
        step?()
    }

    public func delete(_ key: StoreKey) throws {
        try lock.withLock {
            if failing.contains(key) { throw StorageError(operation: "delete \(key.rawValue)", status: -1) }
            items[key] = nil
        }
    }

    public func create(_ data: Data, for key: StoreKey) throws -> Bool {
        try lock.withLock {
            if failing.contains(key) { throw StorageError(operation: "create \(key.rawValue)", status: -1) }
            guard items[key] == nil else { return false }
            items[key] = data
            return true
        }
    }

    public func replace(_ data: Data, for key: StoreKey) throws -> Bool {
        try lock.withLock {
            if failing.contains(key) { throw StorageError(operation: "replace \(key.rawValue)", status: -1) }
            guard items[key] != nil else { return false }
            items[key] = data
            return true
        }
    }
}
