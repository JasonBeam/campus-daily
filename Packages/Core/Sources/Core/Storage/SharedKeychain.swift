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
        // The probe an earlier launch added would make this add fail as a duplicate: start clean.
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

    /// `<TeamPrefix>.<bundle id>.shared`, from the default group (`sharedGroup(defaultGroup:)`).
    /// Nil while the default group can't be read. A build whose signature lacks the shared group
    /// falls back to the default group, and the widget simply has no data.
    public static var accessGroup: String? { groups.sharedGroup }

    /// The app's private group, or nil in the widget (its default group is the shared one).
    public static var privateGroup: String? { groups.privateGroup }

    /// The shared group, from the group a write without one lands in: the entitlements list the
    /// app's private group first, so the app's shared group is that plus `.shared`; the widget's
    /// only group is the shared one. Taken from the signature, not Info.plist, so an IPA
    /// re-signed under another bundle id still has the app and the widget meet in one group.
    /// A re-signer that grants a wildcard (`TEAM.*`) makes each default group the process's own
    /// bundle id, `TEAM.<app id>.balances` in the widget: a widget default group that isn't a
    /// `.shared` one then gives way to `TEAM.<bundle id without .balances>.shared`, the app's
    /// (as `AppIdentity.appGroupCandidates` does for the App Group). A signature that doesn't
    /// allow that group answers missing-entitlement, and the store falls back to no group.
    public static func sharedGroup(defaultGroup group: String, inExtension: Bool, bundleID: String? = nil) -> String {
        guard inExtension else { return group + ".shared" }
        guard !group.hasSuffix(".shared"), var app = bundleID, !app.isEmpty,
              let team = group.split(separator: ".", maxSplits: 1).first, team.count < group.count else { return group }
        if app.hasSuffix(".balances") { app = String(app.dropLast(".balances".count)) }
        return String(team) + "." + app + ".shared"
    }

    /// The app's default group is its private one; the widget has none.
    public static func privateGroup(defaultGroup group: String, inExtension: Bool) -> String? {
        inExtension ? nil : group
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
    /// Held while a probe runs (its delete and add).
    private let probing = NSLock()
    /// The widget (`AppIdentity.inExtension`): its default group is the shared one.
    private let inExtension: Bool
    /// The bundle id this process runs under (the widget's ends in `.balances`).
    private let bundleID: String?

    public init(inExtension: Bool = AppIdentity.inExtension, bundleID: String? = Bundle.main.bundleIdentifier,
                _ probe: @escaping @Sendable () -> String?) {
        self.inExtension = inExtension; self.bundleID = bundleID; self.probe = probe
    }

    /// One probe at a time: two first uses at once would interleave their delete and add, and
    /// the second add would fail as a duplicate. The one that waited takes the first's answer.
    public var defaultGroup: String? {
        if let known = cached.withLock({ $0 }) { return known }
        return probing.withLock {
            if let known = cached.withLock({ $0 }) { return known }
            guard let found = probe() else { return nil }
            cached.withLock { $0 = found }
            return found
        }
    }

    public var sharedGroup: String? {
        defaultGroup.map { SharedKeychain.sharedGroup(defaultGroup:$0, inExtension:inExtension, bundleID:bundleID) }
    }
    public var privateGroup: String? { defaultGroup.flatMap { SharedKeychain.privateGroup(defaultGroup:$0, inExtension:inExtension) } }
}
