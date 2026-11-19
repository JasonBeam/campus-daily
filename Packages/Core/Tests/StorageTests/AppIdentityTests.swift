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
    }

    /// No keys (or empty ones): no App Group and no shared keychain group, never a guessed one.
    func testMissingKeysGiveNoGroups() {
        for info in [nil, [:], ["AppGroupIdentifier": "", "KeychainGroupIdentifier": ""]] as [[String: Any]?] {
            let identity = AppIdentity(info: info)
            XCTAssertNil(identity.appGroup)
            XCTAssertNil(identity.keychainGroup)
        }
    }

    /// An IPA re-signed under another bundle id still carries the default ids in Info.plist. The
    /// shared keychain group comes from the group the process writes to by default (the
    /// re-signer's), so the app and the widget still meet there.
    func testReSignedBuildsShareTheKeychainGroupOfTheirSignature() {
        XCTAssertEqual(SharedKeychain.sharedGroup(defaultGroup: "TEAM000042.org.example.daily", inExtension: false),
                       "TEAM000042.org.example.daily.shared")
        XCTAssertEqual(SharedKeychain.sharedGroup(defaultGroup: "TEAM000042.org.example.daily.shared", inExtension: true),
                       "TEAM000042.org.example.daily.shared")
        XCTAssertEqual(SharedKeychain.privateGroup(defaultGroup: "TEAM000042.org.example.daily", inExtension: false),
                       "TEAM000042.org.example.daily")
        XCTAssertNil(SharedKeychain.privateGroup(defaultGroup: "TEAM000042.org.example.daily.shared", inExtension: true))
    }

    /// The App Group named in Info.plist first; when it has no container (re-signed), `group.`
    /// plus the bundle id the process runs under, the widget's without `.balances`.
    func testReSignedBuildsTryTheAppGroupOfTheirBundleID() {
        XCTAssertEqual(AppIdentity.appGroupCandidates(named: "group.org.zaxh.xiaorichang", bundleID: "org.example.daily", inExtension: false),
                       ["group.org.zaxh.xiaorichang", "group.org.example.daily"])
        XCTAssertEqual(AppIdentity.appGroupCandidates(named: "group.org.zaxh.xiaorichang", bundleID: "org.example.daily.balances", inExtension: true),
                       ["group.org.zaxh.xiaorichang", "group.org.example.daily"])
        XCTAssertEqual(AppIdentity.appGroupCandidates(named: "group.org.example.daily", bundleID: "org.example.daily", inExtension: false),
                       ["group.org.example.daily"], "the same group is tried once")
        XCTAssertEqual(AppIdentity.appGroupCandidates(named: nil, bundleID: "org.example.daily", inExtension: false), ["group.org.example.daily"])
        XCTAssertEqual(AppIdentity.appGroupCandidates(named: "group.org.example.daily", bundleID: nil, inExtension: false), ["group.org.example.daily"])
        XCTAssertEqual(AppIdentity.appGroupCandidates(named: nil, bundleID: nil, inExtension: true), [])

        let candidates = ["group.org.zaxh.xiaorichang", "group.org.example.daily"]
        XCTAssertEqual(AppIdentity.firstWithContainer(candidates) { _ in true }, "group.org.zaxh.xiaorichang")
        XCTAssertEqual(AppIdentity.firstWithContainer(candidates) { $0 == "group.org.example.daily" }, "group.org.example.daily")
        XCTAssertNil(AppIdentity.firstWithContainer(candidates) { _ in false })
    }

    /// With the bundle id in Base.xcconfig, every identifier is the one architecture §4.2 lists
    /// (org.zaxh.xiaorichang; Android keeps its own com.beamjason.xiaorichang).
    func testDefaultBundleIdGivesTheListedIdentifiers() throws {
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
        XCTAssertEqual(app.appGroup, "group.org.zaxh.xiaorichang")
        XCTAssertEqual(app.keychainGroup, "org.zaxh.xiaorichang")
        XCTAssertEqual(AppIdentity(info: widgetInfo), app, "the widget reads the app's groups, not its own bundle id")
        XCTAssertEqual(appInfo["BGTaskSchedulerPermittedIdentifiers"] as? [String], ["org.zaxh.xiaorichang.refresh"])

        for entitlements in [appEntitlements, widgetEntitlements] {
            XCTAssertEqual(entitlements["com.apple.security.application-groups"] as? [String], ["group.org.zaxh.xiaorichang"])
        }
        XCTAssertEqual(appEntitlements["keychain-access-groups"] as? [String],
                       ["$(AppIdentifierPrefix)org.zaxh.xiaorichang", "$(AppIdentifierPrefix)org.zaxh.xiaorichang.shared"])
        XCTAssertEqual(widgetEntitlements["keychain-access-groups"] as? [String],
                       ["$(AppIdentifierPrefix)org.zaxh.xiaorichang.shared"])
    }

    /// Nothing in these files names the default identity: they carry only the build setting,
    /// neither today's bundle id nor the one iOS builds used before (still Android's).
    func testIdentifiersAreFilledFromTheBuildSetting() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["App/Resources/Info.plist", "Widget/Info.plist", "App/Resources/App.entitlements", "Widget/Widget.entitlements"] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for id in ["org.zaxh.xiaorichang", "com.beamjason.xiaorichang"] {
                XCTAssertFalse(text.contains(id), "\(path) names \(id)")
            }
        }
    }
}
