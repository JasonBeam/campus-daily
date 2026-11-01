import Foundation

/// Keychain item names (architecture §4.1). Service = `com.beamjason.xiaorichang.<name>.v1`,
/// account = `default`.
public enum StoreKey: String, Sendable, CaseIterable {
    case schoolPortal = "school.portal"
    case schoolEcykt = "school.ecykt"
    case schoolProfile = "school.profile"
    /// The school account, and its password only if the user chose to save it.
    case schoolPassword = "school.password"
    /// The browser id the school login sees from this install (random, not personal).
    case schoolDevice = "school.device"
    case showerBinding = "water.binding"
    case showerSession = "water.session"
    case laundryAccount = "laundry.account"
    case laundryCheckout = "laundry.checkout"
    case sharedSnapshot = "shared.snapshot"
    case sharedReminderLines = "shared.reminderLines"
    /// Where builds before the lease file kept the refresh lease (a random owner id and an
    /// expiry). Only deleted now: `SchoolRefreshStack` removes a leftover at launch.
    case sharedRefreshLease = "shared.refreshLease"
    /// The credential-lifetime lines (kind and minutes only) for the exported diagnostics.
    case sharedCredentialLog = "shared.credentialLog"
    /// A reset is under way, since when (`ResetMarker`). Holds a time only.
    case sharedResetMarker = "shared.resetMarker"

    public static let servicePrefix = "com.beamjason.xiaorichang."
    public static let account = "default"

    public var service: String { Self.servicePrefix + rawValue + ".v1" }

    public enum Accessibility: String, Sendable {
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlockThisDeviceOnly
    }

    /// Every item is readable after the first unlock, so the background refresh and the widget
    /// work while the phone is locked. None leaves this device (no iCloud Keychain, no backup
    /// restore onto another phone).
    public var accessibility: Accessibility { .afterFirstUnlockThisDeviceOnly }

    /// Written to the shared access group so the widget extension can read them: the snapshot and
    /// reminder lines it shows, the lifetime lines its refresh writes, the reset marker, and everything its own school refresh needs (card session, portal
    /// token, dorm/meter profile, saved account and password, login device id). Hot-water and
    /// laundry items live only in the app's private group, which the widget is not entitled to.
    public var isShared: Bool {
        switch self {
        case .sharedSnapshot, .sharedReminderLines, .sharedRefreshLease, .sharedCredentialLog, .sharedResetMarker, .schoolEcykt, .schoolPortal, .schoolProfile, .schoolPassword, .schoolDevice:
            return true
        case .showerBinding, .showerSession, .laundryAccount, .laundryCheckout: return false
        }
    }
}

/// Raw secure storage of small blobs.
public protocol SecureStore: Sendable {
    func read(_ key: StoreKey) throws -> Data?
    func write(_ data: Data, for key: StoreKey) throws
    func delete(_ key: StoreKey) throws
    /// Writes only when no item exists, atomically across processes. False = one exists.
    func create(_ data: Data, for key: StoreKey) throws -> Bool
    /// Writes only over an item that exists, atomically across processes. False = none exists
    /// (it was deleted meanwhile), and nothing is written.
    func replace(_ data: Data, for key: StoreKey) throws -> Bool
}

public extension SecureStore {
    func readJSON<T: Decodable>(_ type: T.Type, _ key: StoreKey) throws -> T? {
        guard let data = try read(key) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw StorageError(operation: "decode \(key.rawValue)", status: -1) }
    }

    func writeJSON<T: Encodable>(_ value: T?, _ key: StoreKey) throws {
        guard let value else { try delete(key); return }
        let data: Data
        do { data = try JSONEncoder().encode(value) }
        catch { throw StorageError(operation: "encode \(key.rawValue)", status: -1) }
        try write(data, for: key)
    }
}

/// UserDefaults keys (all prefixed `xrc.`).
public enum PreferenceKey {
    public static let prefix = "xrc."
    public static func reminder(_ name: String) -> String { prefix + "reminder." + name }
    public static let laundryAckFailedOrder = prefix + "laundry.ackFailedOrder"
    public static let showerNeedsResidenceReview = prefix + "water.needsResidenceReview"
    /// Bool, absent = on (school laundry shown).
    public static let schoolLaundry = prefix + "laundry.school"
}
