import XCTest
@testable import Core
import CoreTestSupport

/// 导出热水诊断 is gone and nothing writes diagnostics any more. What older builds left on the
/// phone (the event file, the credential-lifetime Keychain item, an export in the temporary
/// folder) is removed at launch, and the Water folder holding the imported config stays out
/// of backups, which the diagnostics file used to do as a side effect.
final class RetiredDiagnosticsTests: XCTestCase {
    var root: URL!
    var support: URL { root.appendingPathComponent("Support", isDirectory: true) }
    var temporary: URL { root.appendingPathComponent("tmp", isDirectory: true) }
    var water: URL { support.appendingPathComponent("Water", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("retired-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: water, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func excluded(_ url: URL) throws -> Bool {
        var fresh = url; fresh.removeAllCachedResourceValues()
        return try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    func testTheLeftoversAreRemovedAndTheImportedConfigStays() throws {
        let events = water.appendingPathComponent("diagnostics.json")
        let imported = water.appendingPathComponent("imported.waterconfig")
        try Data("[]".utf8).write(to: events)
        try Data("{}".utf8).write(to: imported)
        let export = temporary.appendingPathComponent("WaterDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: export.appendingPathComponent("XiaoRiChang-water-diagnostics.json"))
        let scans = support.appendingPathComponent("WaterSession", isDirectory: true)
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: scans.appendingPathComponent("last-scan.json"))
        let store = InMemorySecureStore()
        try store.write(Data("[]".utf8), for: .sharedCredentialLog)
        try store.write(Data("keep".utf8), for: .sharedSnapshot)

        RetiredDiagnostics.removeLeftovers(store: store, applicationSupport: support, temporary: temporary)

        XCTAssertFalse(FileManager.default.fileExists(atPath: events.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scans.appendingPathComponent("last-scan.json").path))
        XCTAssertNil(try store.read(.sharedCredentialLog))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path), "the imported config is not a diagnostic")
        XCTAssertEqual(try store.read(.sharedSnapshot), Data("keep".utf8))
        XCTAssertTrue(try excluded(water), "a config imported before stays out of backups")
        XCTAssertTrue(AppReset.keychainItems.contains(.sharedCredentialLog), "reset deletes it too")

        // Every launch: nothing left is fine.
        RetiredDiagnostics.removeLeftovers(store: store, applicationSupport: support, temporary: temporary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))
    }

    func testNoWaterFolderIsNotCreated() throws {
        try FileManager.default.removeItem(at: water)
        RetiredDiagnostics.removeLeftovers(store: InMemorySecureStore(), applicationSupport: support, temporary: temporary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: water.path))
    }

    func testTheFolderOfAnImportIsKeptOutOfBackups() throws {
        try FileManager.default.removeItem(at: water)
        let target = water.appendingPathComponent("imported.waterconfig")
        try ShowerImportFolder.prepare(for: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: water.path))
        XCTAssertTrue(try excluded(water))
    }
}
