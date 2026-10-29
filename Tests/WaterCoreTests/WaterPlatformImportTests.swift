import XCTest
@testable import WaterCore

final class WaterPlatformImportTests: XCTestCase {
    private func seed() -> [String:Any] {
        ["secret":"fixture-secret","sid":"fixture-provider","bleName":"fixture-ble","typeID":1,"version":1]
    }
    private func parse(_ value: [String:Any]) throws -> WaterPlatformProfile {
        try .parseImport(JSONSerialization.data(withJSONObject:value))
    }
    func testFreshInstallCanAcceptPlatformThenCreateOnlyAuthenticatedResidence() throws {
        let profile = try parse(seed())
        let encoded = try JSONEncoder().encode(profile)
        let persisted = try WaterPlatformProfile.parseImport(encoded)
        let first = try persisted.configuration(student:"own-user",school:"own-school",machine:"11223344")
        XCTAssertEqual(first.studentID,"own-user")
        XCTAssertEqual(first.machineID,"11223344")
        // A common platform file has no account or binding to reuse for another student.
        let second = try persisted.configuration(student:"another-own-user",school:"own-school",machine:"55667788")
        XCTAssertEqual(second.studentID,"another-own-user")
        XCTAssertEqual(second.machineID,"55667788")
    }
    func testRejectsPersonalConfigurationInsteadOfSilentlyCopyingBinding() {
        for field in ["student_id","studentID","school_id","machine_id","dorm_room","acc_token","address","base_url"] {
            var value = seed(); value[field] = "not-allowed"
            XCTAssertThrowsError(try parse(value),field)
        }
    }
    func testRejectsIncompleteMalformedOrOversizedPlatformFiles() throws {
        for key in seed().keys {
            var value = seed(); value.removeValue(forKey:key)
            XCTAssertThrowsError(try parse(value))
        }
        for (key,value): (String,Any) in [("secret"," "),("sid","x\ny"),("bleName","bad\nname"),("typeID",-1),("version",0),("version",true),("typeID","1")] {
            var root = seed(); root[key] = value
            XCTAssertThrowsError(try parse(root))
        }
        XCTAssertThrowsError(try WaterPlatformProfile.parseImport(Data(repeating:32,count:8193)))
    }
}
