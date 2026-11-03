import XCTest
import Core

/// The App Group, the keychain groups and the background task id follow `APP_BUNDLE_IDENTIFIER`
/// (Info.plist and the entitlements are filled from it at build time) instead of being written
/// into the code.
final class AppIdentityTests: XCTestCase {
    func testIdentityComesFromTheInfoPlistKeys() {
        let identity = AppIdentity(info: ["AppGroupIdentifier": "group.org.example.daily",
                                          "KeychainGroupIdentifier": "org.example.daily"])
        XCTAssertEqual(identity.appGroup, "group.org.example.daily")
        XCTAssertEqual(identity.keychainGroup, "org.example.daily")
        XCTAssertEqual(identity.sharedKeychainGroup, "org.example.daily.shared")
    }

    /// No keys (or empty ones): no App Group and no shared keychain group, never a guessed one.
    func testMissingKeysGiveNoGroups() {
        for info in [nil, [:], ["AppGroupIdentifier": "", "KeychainGroupIdentifier": ""]] as [[String: Any]?] {
            let identity = AppIdentity(info: info)
            XCTAssertNil(identity.appGroup)
            XCTAssertNil(identity.keychainGroup)
            XCTAssertNil(identity.sharedKeychainGroup)
        }
    }

    /// A build signed under another bundle id finds its own shared group, not the default one.
    func testSharedGroupFollowsTheBuildsIdentity() {
        let shared = AppIdentity(info: ["KeychainGroupIdentifier": "org.example.daily"]).sharedKeychainGroup
        XCTAssertEqual(SharedKeychain.accessGroup(teamPrefixedFrom: "TEAM000042.org.example.daily", sharedGroup: shared),
                       "TEAM000042.org.example.daily.shared")
        XCTAssertNil(SharedKeychain.accessGroup(teamPrefixedFrom: "TEAM000042.org.example.daily", sharedGroup: nil))
        XCTAssertEqual(SharedKeychain.privateGroup(defaultGroup: "TEAM000042.org.example.daily", sharedGroup: nil),
                       "TEAM000042.org.example.daily")
    }

    /// With the bundle id in Base.xcconfig, every identifier is exactly what earlier builds
    /// used, so installed copies keep their App Group, Keychain items and background task.
    func testDefaultBundleIdKeepsTodaysIdentifiers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let xcconfig = try String(contentsOf: root.appendingPathComponent("Configuration/Base.xcconfig"), encoding: .utf8)
        let line = try XCTUnwrap(xcconfig.split(separator: "\n").first { $0.hasPrefix("APP_BUNDLE_IDENTIFIER") })
        let bundleID = line.split(separator: "=", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
        func plist(_ path: String) throws -> [String: Any] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                .replacingOccurrences(of: "$(APP_BUNDLE_IDENTIFIER)", with: bundleID)
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any], path)
        }
        let appInfo = try plist("App/Resources/Info.plist"), widgetInfo = try plist("Widget/Info.plist")
        let appEntitlements = try plist("App/Resources/App.entitlements")
        let widgetEntitlements = try plist("Widget/Widget.entitlements")

        let app = AppIdentity(info: appInfo)
        XCTAssertEqual(app.appGroup, "group.com.beamjason.xiaorichang")
        XCTAssertEqual(app.keychainGroup, "com.beamjason.xiaorichang")
        XCTAssertEqual(app.sharedKeychainGroup, "com.beamjason.xiaorichang.shared")
        XCTAssertEqual(AppIdentity(info: widgetInfo), app, "the widget reads the app's groups, not its own bundle id")
        XCTAssertEqual(appInfo["BGTaskSchedulerPermittedIdentifiers"] as? [String], ["com.beamjason.xiaorichang.refresh"])

        for entitlements in [appEntitlements, widgetEntitlements] {
            XCTAssertEqual(entitlements["com.apple.security.application-groups"] as? [String], ["group.com.beamjason.xiaorichang"])
        }
        XCTAssertEqual(appEntitlements["keychain-access-groups"] as? [String],
                       ["$(AppIdentifierPrefix)com.beamjason.xiaorichang", "$(AppIdentifierPrefix)com.beamjason.xiaorichang.shared"])
        XCTAssertEqual(widgetEntitlements["keychain-access-groups"] as? [String],
                       ["$(AppIdentifierPrefix)com.beamjason.xiaorichang.shared"])
    }

    /// Nothing in the code names the default identity any more: the source files carry only
    /// the build setting.
    func testIdentifiersAreFilledFromTheBuildSetting() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["App/Resources/Info.plist", "Widget/Info.plist", "App/Resources/App.entitlements", "Widget/Widget.entitlements"] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(text.contains("com.beamjason"), path)
        }
    }
}
