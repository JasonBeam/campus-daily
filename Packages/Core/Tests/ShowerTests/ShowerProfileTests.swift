import XCTest
import Foundation
@testable import Core
import CoreTestSupport

// MARK: - Profiles and vault

final class ShowerProfileTests: XCTestCase {
    let valid = #"{"secret":"fixture-secret ~/+","sid":"fixture-sid=1","bleName":"fixture-ble","typeID":1,"version":3}"#

    func testWaterConfigFileIsExactlyFiveKeys() throws {
        let p = try ShowerConfigFile.parse(Data(valid.utf8), source: .bundled)
        XCTAssertEqual(p, ShowerPlatformProfile(secret: "fixture-secret ~/+", sid: "fixture-sid=1", bleName: "fixture-ble", typeId: "1", version: "3"))
        let src = ShowerProfileSource.imported(fileName: "a.waterconfig")
        let unreadable = [
            #"{"secret":"s","sid":"x","bleName":"b","typeID":1,"version":3,"studentID":"S1"}"#,
            #"{"secret":"s","sid":"x","bleName":"b","typeID":"1","version":3}"#,
            #"{"secret":"s","sid":"x","bleName":"b","typeID":1}"#,
            "[]", "not json",
        ]
        for text in unreadable {
            XCTAssertThrowsError(try ShowerConfigFile.parse(Data(text.utf8), source: src), text) {
                XCTAssertEqual($0 as? ShowerProfileError, .unreadable(src))
            }
        }
        for text in [#"{"secret":" ","sid":"x","bleName":"b","typeID":1,"version":3}"#,
                     #"{"secret":"s","sid":"x","bleName":"b","typeID":1,"version":0}"#,
                     #"{"secret":"s","sid":"x\n","bleName":"b","typeID":1,"version":3}"#] {
            XCTAssertThrowsError(try ShowerConfigFile.parse(Data(text.utf8), source: src), text) {
                XCTAssertEqual($0 as? ShowerProfileError, .incomplete(src))
            }
        }
        XCTAssertThrowsError(try ShowerConfigFile.parse(Data(count: ShowerConfigFile.maxBytes + 1), source: src))
        XCTAssertEqual(try ShowerProfileResolver.decodeProfile(Data(valid.utf8), source: .bundled).typeId, "1", "typeID key accepted")
    }

    func testLoaderResolvesBothSources() async throws {
        let validData = Data(valid.utf8)
        let loader = ShowerProfileLoader(bundled: { validData }, imported: { $0 == "mine.waterconfig" ? validData : nil })
        guard case .local(let p, .bundled) = try await loader.resolve(.bundled) else { return XCTFail() }
        XCTAssertEqual(p.bleName, "fixture-ble")
        guard case .local(_, .imported) = try await loader.resolve(.imported(fileName: "mine.waterconfig")) else { return XCTFail() }
        let missing = ShowerProfileSource.imported(fileName: "other")
        await assertProfileError(.missing(missing)) { _ = try await loader.resolve(missing) }
        struct Boom: Error {}
        let broken = ShowerProfileLoader(bundled: { throw Boom() }, imported: { _ in nil })
        await assertProfileError(.unreadable(.bundled)) { _ = try await broken.resolve(.bundled) }

        let empty = ShowerProfileLoader(bundled: { nil }, imported: { _ in validData })
        let first = await ShowerProfileResolver.firstUsable([.bundled, .imported(fileName: "x")], provider: empty)
        guard case .success(.local(_, .imported)) = first else { return XCTFail("\(first)") }
    }

    func assertProfileError(_ expected: ShowerProfileError, file: StaticString = #filePath, line: UInt = #line,
                            _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? ShowerProfileError, expected, file: file, line: line) }
    }

    func testVaultRoundTripAndFailClosedWrites() throws {
        let store = InMemorySecureStore()
        let vault = StoredShowerVault(store: store)
        XCTAssertNil(try vault.binding())
        XCTAssertNil(try vault.showerState())
        let binding = ShowerBinding(studentId: "S1", schoolId: "20021", machineId: "1a2b3c4d", roomId: "r", roomLabel: "99栋 991",
                                   machineName: "9-901", peripheralID: "P")
        XCTAssertEqual(binding.machineId, "1A2B3C4D")
        try vault.saveBinding(binding)
        XCTAssertEqual(try vault.binding(), binding)
        let state = ShowerState(phase: .settling, machineID: "1A2B3C4D", consumption: "55", failure: nil)
        try vault.saveShowerState(state)
        XCTAssertEqual(try vault.showerState(), state)
        try vault.saveShowerState(nil)
        XCTAssertNil(try vault.showerState())

        store.failWrites(to: .showerSession)
        XCTAssertThrowsError(try vault.saveShowerState(state))
        XCTAssertFalse(binding.description.contains("S1"))
    }
}
