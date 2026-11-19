import XCTest
@testable import XiaoRiChang

/// The app's PrivacyInfo.xcprivacy says what the crash reports collect and why the app reads
/// UserDefaults.
final class PrivacyManifestTests: XCTestCase {
    private func manifest() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "PrivacyInfo.xcprivacy is not in the app bundle")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    func testItDoesNotTrack() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String]) ?? [], [])
    }

    func testCrashDataIsCollectedForAppFunctionalityOnly() throws {
        let types = try XCTUnwrap(manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let crash = types.filter { $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeCrashData" }
        XCTAssertEqual(crash.count, 1)
        let entry = try XCTUnwrap(crash.first)
        XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, false)
        XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                       ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
    }

    func testUserDefaultsIsDeclaredWithItsReason() throws {
        let apis = try XCTUnwrap(manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = apis.filter { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }
        XCTAssertEqual(defaults.count, 1)
        let reasons = try XCTUnwrap(defaults.first?["NSPrivacyAccessedAPITypeReasons"] as? [String])
        XCTAssertTrue(reasons.contains("CA92.1"), "\(reasons)")
    }
}
