import Foundation
import Security
import os

/// The Keychain store of this process (no App Group). The app lists two groups in App.entitlements:
/// its private group first (the default for writes without a group), then the shared group, which
/// is the only one Widget.entitlements lists.
public enum SharedKeychain {
    /// The group a write without a group lands in, read from this build's own signature: the
    /// private group in the app, the shared group in the widget. Nil while it can't be read
    /// (for example before the first unlock); it is probed again on the next use, so one early
    /// failure does not send the whole process's items to the wrong group.
    public static let groups = KeychainGroupProbe {
        let probe: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
                                   kSecAttrService as String:StoreKey.servicePrefix + "probe",
                                   kSecAttrAccount as String:StoreKey.account,
                                   kSecUseDataProtectionKeychain as String:true]
        // Older builds left a probe in the shared group; start clean so the answer is today's default.
        SecItemDelete(probe as CFDictionary)
        var add = probe
        add[kSecValueData as String] = Data()
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecReturnAttributes as String] = true
        var out: CFTypeRef?
        guard SecItemAdd(add as CFDictionary, &out) == errSecSuccess else { return nil }
        return (out as? [String:Any])?[kSecAttrAccessGroup as String] as? String
    }

    public static var defaultGroup: String? { groups.defaultGroup }

    /// `<TeamPrefix>.<bundle id>.shared`. Nil when the prefix can't be read (re-signed without
    /// keychain groups) or Info.plist names no keychain group: the store then keeps everything
    /// in the default group and the widget simply has no data.
    public static var accessGroup: String? { groups.sharedGroup }

    /// The app's private group, or nil in the widget (its default group is the shared one).
    public static var privateGroup: String? { groups.privateGroup }

    /// `<TeamPrefix>.` + `sharedGroup`, taking the team prefix from any group this build wrote to.
    /// `sharedGroup` is the shared group's name after the prefix, from this build's Info.plist.
    public static func accessGroup(teamPrefixedFrom group: String,
                                   sharedGroup: String? = AppIdentity.main.sharedKeychainGroup) -> String? {
        guard let sharedGroup, let dot = group.firstIndex(of:"."), dot != group.startIndex else { return nil }
        return String(group[..<dot]) + "." + sharedGroup
    }

    /// The default group is private unless it is the shared group itself.
    public static func privateGroup(defaultGroup group: String,
                                    sharedGroup: String? = AppIdentity.main.sharedKeychainGroup) -> String? {
        group == accessGroup(teamPrefixedFrom:group, sharedGroup:sharedGroup) ? nil : group
    }

    public static let keychainStore = KeychainSecureStore(backend:SecItemKeychainBackend(), groups:groups)
    public static var store: SecureStore { keychainStore }

    /// Moves items an older build left in the other group; call once at app launch.
    @discardableResult
    public static func migrateItemGroups() -> [StoreKey] { keychainStore.migrateItemGroups() }
}

/// The default access group, probed until a probe succeeds and then kept for the process.
/// A failed probe is never cached.
public final class KeychainGroupProbe: Sendable {
    private let probe: @Sendable () -> String?
    private let cached = OSAllocatedUnfairLock<String?>(initialState: nil)
    /// The shared group's name after the team prefix (`AppIdentity.sharedKeychainGroup`).
    private let sharedName: String?

    public init(sharedGroup: String? = AppIdentity.main.sharedKeychainGroup, _ probe: @escaping @Sendable () -> String?) {
        self.sharedName = sharedGroup; self.probe = probe
    }

    public var defaultGroup: String? {
        if let known = cached.withLock({ $0 }) { return known }
        guard let found = probe() else { return nil }
        cached.withLock { $0 = found }
        return found
    }

    public var sharedGroup: String? { defaultGroup.flatMap { SharedKeychain.accessGroup(teamPrefixedFrom:$0, sharedGroup:sharedName) } }
    public var privateGroup: String? { defaultGroup.flatMap { SharedKeychain.privateGroup(defaultGroup:$0, sharedGroup:sharedName) } }
}
