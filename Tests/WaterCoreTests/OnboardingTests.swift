import XCTest
@testable import WaterCore

final class OnboardingTests: XCTestCase {
    private func session(_ overrides: [String:Any] = [:]) throws -> Data {
        var state: [String:Any] = ["logintoken":"fictional-token", "schoolid":"test-area",
            "loginInfo":["syscustid":"fictional-person"], "custInfo":["custid":"fictional-card"]]
        overrides.forEach { state[$0.key] = $0.value }
        return try JSONSerialization.data(withJSONObject:state)
    }
    func testCardLoginDoesNotRequirePowerRoomOrTimestamp() throws {
        let value = try OfficialCampusSession.parse(session())
        XCTAssertEqual(value.custid,"fictional-card")
        XCTAssertEqual(value.timestamp,"")
        XCTAssertEqual(value.buildingID,"")
        XCTAssertEqual(value.dormRoom,"")
    }
    func testMissingTokenRejected() throws {
        XCTAssertThrowsError(try OfficialCampusSession.parse(session(["logintoken":""])))
    }
    func testMissingCardRejectedRatherThanGuessing() throws {
        XCTAssertThrowsError(try OfficialCampusSession.parse(session(["custInfo":[:]])))
    }
    func testNumericIdentifiersSupported() throws {
        let value = try OfficialCampusSession.parse(session(["schoolid":123,"custInfo":["custid":456]]))
        XCTAssertEqual(value.areacode,"123")
        XCTAssertEqual(value.custid,"456")
    }
    func testBooleanCardIsNotAnIdentifier() throws {
        XCTAssertThrowsError(try OfficialCampusSession.parse(session(["custInfo":["custid":true]])))
    }
    func testHeaderInjectionRejected() throws {
        XCTAssertThrowsError(try OfficialCampusSession.parse(session(["logintoken":"token\r\nInjected: yes"])))
    }
}
