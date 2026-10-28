import XCTest
@testable import WaterCore

final class CampusElectricityTests: XCTestCase {
    private func meter(_ id: String = "test-meter") -> [String:Any] {
        ["comAddress":id,"piplineName":"测试寝室","remaining":"120.25","leftMoney":"85.38","preUseDay":"4.5","updateDateTime":"2026-10-26 01:00:00"]
    }
    func testSeparateMoneyAndKilowattHours() throws {
        let value = try CampusElectricityParser.meters([meter()])[0]
        XCTAssertEqual(value.remainingKWh,Decimal(string:"120.25"))
        XCTAssertEqual(value.balanceYuan,Decimal(string:"85.38"))
        XCTAssertEqual(value.yesterdayKWh,Decimal(string:"4.5"))
    }
    func testMultipleMetersNeedSelection() throws {
        let meters = try CampusElectricityParser.meters([meter("a"),meter("b")])
        XCTAssertThrowsError(try CampusElectricityParser.select(meters,id:""))
        XCTAssertEqual(try CampusElectricityParser.select(meters,id:"b").id,"b")
        XCTAssertThrowsError(try CampusElectricityParser.select(meters,id:"missing"))
    }
    func testInvalidRemainingCannotBeReportedAsZero() {
        var data = meter(); data["remaining"] = true
        XCTAssertThrowsError(try CampusElectricityParser.meters([data]))
        data["remaining"] = "--"
        XCTAssertThrowsError(try CampusElectricityParser.meters([data]))
    }
    func testZeroAndNegativeBalancesArePreserved() throws {
        var data = meter(); data["remaining"] = "0"; data["leftMoney"] = "-0.75"
        let value = try CampusElectricityParser.meters([data])[0]
        XCTAssertEqual(value.remainingKWh,0); XCTAssertEqual(value.balanceYuan,Decimal(string:"-0.75"))
    }
    func testFailedPowerRefreshKeepsLastValueAndTimestamp() throws {
        let date = Date(timeIntervalSince1970:100)
        var snapshot = CampusSnapshot(owner:"test")
        snapshot.recordPower(.success(try CampusElectricityParser.meters([meter()])[0]),at:date)
        snapshot.recordPower(.failure(.expired),at:date.addingTimeInterval(10))
        XCTAssertEqual(snapshot.electricity?.remainingKWh,Decimal(string:"120.25"))
        XCTAssertEqual(snapshot.powerFetchedAt,date)
        XCTAssertTrue(snapshot.powerIsStale(at:date.addingTimeInterval(10)))
        XCTAssertTrue(snapshot.balanceIsStale(at:date))
    }
    func testDuplicateBuildingOrMeterIDsRejected() {
        XCTAssertThrowsError(try CampusElectricityParser.meters([meter(),meter()]))
        XCTAssertThrowsError(try CampusElectricityParser.buildings([["buildingID":"a","buildingName":"A"],["buildingID":"a","buildingName":"B"]]))
    }
    func testOldSnapshotStillDecodesWithoutPowerFields() throws {
        let data = Data(#"{"owner":"old"}"#.utf8)
        let value = try JSONDecoder().decode(CampusSnapshot.self,from:data)
        XCTAssertNil(value.electricity)
        XCTAssertTrue(value.powerIsStale())
    }
}
