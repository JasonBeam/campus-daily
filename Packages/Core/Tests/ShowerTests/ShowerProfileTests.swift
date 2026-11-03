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
        XCTAssertFalse("\(p)".contains("fixture-secret"), "the secret is never printed")
    }

    /// The imported file when it reads as a profile, else the bundled one; nil when neither does.
    func testTheImportedProfileComesFirstThenTheBundledOne() throws {
        let bundled = try ShowerConfigFile.parse(Data(valid.utf8), source: .bundled)
        let mine = #"{"secret":"fixture-mine","sid":"fixture-sid=2","bleName":"fixture-ble","typeID":1,"version":4}"#
        struct Boom: Error {}
        XCTAssertEqual(ShowerProfileLoader.localProfile(imported: { Data(mine.utf8) }, bundled: { Data(self.valid.utf8) })?.version, "4")
        XCTAssertEqual(ShowerProfileLoader.localProfile(imported: { nil }, bundled: { Data(self.valid.utf8) }), bundled)
        XCTAssertEqual(ShowerProfileLoader.localProfile(imported: { throw Boom() }, bundled: { Data(self.valid.utf8) }), bundled,
                       "an unreadable import falls back")
        XCTAssertEqual(ShowerProfileLoader.localProfile(imported: { Data("not json".utf8) }, bundled: { Data(self.valid.utf8) }), bundled,
                       "an import that is not a profile falls back")
        let blank = #"{"secret":" ","sid":"x","bleName":"b","typeID":1,"version":3}"#
        XCTAssertEqual(ShowerProfileLoader.localProfile(imported: { Data(blank.utf8) }, bundled: { Data(self.valid.utf8) }), bundled,
                       "an incomplete import falls back")
        XCTAssertNil(ShowerProfileLoader.localProfile(imported: { nil }, bundled: { nil }))
        XCTAssertNil(ShowerProfileLoader.localProfile(imported: { nil }, bundled: { throw Boom() }))
        XCTAssertNil(ShowerProfileLoader.localProfile(imported: { nil }, bundled: { Data(blank.utf8) }))
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
