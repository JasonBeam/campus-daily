import Foundation

/// The identifiers this build is signed for: the App Group both targets share and the keychain
/// group name (after the team prefix). Both come from Info.plist keys that the build fills from
/// `APP_BUNDLE_IDENTIFIER`, the same setting the entitlements use, so a build under another
/// bundle id finds its own groups. The widget carries the app's values, not its own bundle id.
/// An IPA re-signed under another bundle id keeps the old values in Info.plist: the App Group
/// then falls back to the bundle id the process runs under (`usableAppGroup`), and the keychain
/// groups come from the group the signature makes the default (`SharedKeychain`).
public struct AppIdentity: Sendable, Equatable {
    public static let appGroupKey = "AppGroupIdentifier"
    public static let keychainGroupKey = "KeychainGroupIdentifier"

    /// `group.<bundle id>`, or nil when Info.plist has no such key (tests, previews).
    public let appGroup: String?
    /// The app's private keychain group without the team prefix: `<bundle id>`. The code
    /// takes the groups from the signature.
    public let keychainGroup: String?

    public init(info: [String: Any]?) {
        func value(_ key: String) -> String? { (info?[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        appGroup = value(Self.appGroupKey)
        keychainGroup = value(Self.keychainGroupKey)
    }

    /// This process's identity, from its own Info.plist.
    public static let main = AppIdentity(info: Bundle.main.infoDictionary)

    /// True in the widget extension (its bundle is an `.appex`), false in the app.
    public static let inExtension = Bundle.main.bundleURL.pathExtension == "appex"

    /// The App Groups to try, in order: the one Info.plist names, then `group.` plus the bundle
    /// id this process runs under (the widget's without `.balances`), which is the group a
    /// re-signer that rewrote the bundle id entitles. Each once.
    public static func appGroupCandidates(named: String?, bundleID: String?, inExtension: Bool) -> [String] {
        var own = bundleID
        if inExtension, let id = own, id.hasSuffix(".balances") { own = String(id.dropLast(".balances".count)) }
        var candidates: [String] = []
        for group in [named, own.map { "group." + $0 }].compactMap({ $0 }) where !candidates.contains(group) {
            candidates.append(group)
        }
        return candidates
    }

    /// The first group this process has a container for, or nil.
    public static func firstWithContainer(_ candidates: [String], hasContainer: (String) -> Bool) -> String? {
        candidates.first(where: hasContainer)
    }

    /// The App Group this process can open (its container exists), or nil when it has none.
    public static let usableAppGroup: String? = firstWithContainer(
        appGroupCandidates(named: main.appGroup, bundleID: Bundle.main.bundleIdentifier, inExtension: inExtension)
    ) { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
}
