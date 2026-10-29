import XCTest
@testable import WaterCore

final class PortalDormAddressTests: XCTestCase {
    func testExplicitResidenceKeepsBuildingUnitFloorAndRoomSeparate() throws {
        let d = try XCTUnwrap(PortalDormAddress.parse("示例校区2栋3号5层504房"))
        XCTAssertEqual(d.shortRoom,"2栋504")
        XCTAssertEqual(d.unit,"3");XCTAssertEqual(d.floor,5)
        XCTAssertTrue(d.matches("示例校区",level:0));XCTAssertTrue(d.matches("2栋",level:1))
        XCTAssertTrue(d.matches("五楼",level:2));XCTAssertTrue(d.matches("504",level:3))
        XCTAssertFalse(d.matches("教师2栋",level:1));XCTAssertFalse(d.matches("其他校区",level:0))
    }
    func testMissingAndAmbiguousAddressesStayManual() {
        for value in ["2504","2栋504","暂无宿舍","示例校区2栋3号5层"] {XCTAssertNil(PortalDormAddress.parse(value))}
    }
    func testMeterRoomDoesNotUseSubstringMatching() throws {
        let d = try XCTUnwrap(PortalDormAddress.parse("示例校区2栋5楼504室"))
        XCTAssertTrue(d.matchesMeterRoom("2栋 · 504"));XCTAssertFalse(d.matchesMeterRoom("12栋504"));XCTAssertFalse(d.matchesMeterRoom("2栋5040"))
    }
    func testPowerRoomLevelNarrowsBeforeRequestingMeters() throws {
        let d = try XCTUnwrap(PortalDormAddress.parse("示例校区2栋3号5层504房"))
        XCTAssertEqual(d.powerBranchCandidates((501...519).map(String.init)),["504"])
        XCTAssertEqual(d.powerBranchCandidates(["1楼","5楼","6楼"]),["5楼"])
        XCTAssertEqual(d.powerBranchCandidates(["2栋","3栋","教师2栋"]),["2栋"])
        XCTAssertEqual(d.powerBranchCandidates(["1号","3号"]),["3号"])
        XCTAssertEqual(d.powerBranchCandidates(["半山公寓","日月湖公寓"]),["半山公寓","日月湖公寓"])
    }
    func testSameResidenceLabelMigrationRetainsMeterButOtherResidenceDoesNot() throws {
        let d = try XCTUnwrap(PortalDormAddress.parse("示例校区2栋3号5层504房"))
        let own = ["示例校区","2栋","五楼","504"]
        XCTAssertTrue(d.keepsPowerBinding(selection:own,savedRoom:"示例校区 · 2栋 · 五楼 · 504",meterRoom:nil))
        XCTAssertTrue(d.keepsPowerBinding(selection:own,savedRoom:"2栋504",meterRoom:nil))
        XCTAssertTrue(d.keepsPowerBinding(selection:own,savedRoom:"旧版标签",meterRoom:"2栋 · 504"))
        XCTAssertFalse(d.keepsPowerBinding(selection:["其他校区","2栋","五楼","504"],savedRoom:"2栋504",meterRoom:"2栋504"))
        XCTAssertFalse(d.keepsPowerBinding(selection:own,savedRoom:"12栋504",meterRoom:"2栋5040"))
        XCTAssertFalse(d.keepsPowerBinding(selection:[],savedRoom:"2栋504",meterRoom:"2栋504"))
    }
    func testResidenceChangeRequiresTwoCompleteAndDifferentAddresses() {
        let original = "示例校区2栋3号5层504房"
        XCTAssertFalse(PortalDormAddress.hasMoved(from:original,to:"示例校区 2栋3号5层504房"))
        XCTAssertTrue(PortalDormAddress.hasMoved(from:original,to:"示例校区2栋3号5层505房"))
        XCTAssertTrue(PortalDormAddress.hasMoved(from:original,to:"其他校区2栋3号5层504房"))
        XCTAssertFalse(PortalDormAddress.hasMoved(from:"",to:original))
        XCTAssertFalse(PortalDormAddress.hasMoved(from:original,to:"暂无宿舍"))
    }
    func testExistingWaterBindingRequiresReviewForChangedOrUnknownOwner() {
        let room = "示例校区2栋3号5层504房"
        func review(_ binding:Bool,_ old:String?,_ new:String,_ from:String,_ to:String)->Bool {
            PortalDormAddress.needsWaterReview(hasBinding:binding,previousOwner:old,currentOwner:new,oldAddress:from,newAddress:to)
        }
        XCTAssertFalse(review(false,nil,"new","",room))
        XCTAssertTrue(review(true,"old","new",room,room))
        XCTAssertTrue(review(true,"old","new",room,""))
        XCTAssertTrue(review(true,nil,"new","",room))
        XCTAssertFalse(review(true,"same","same",room,""))
        XCTAssertTrue(review(true,"same","same",room,"示例校区2栋3号5层505房"))
    }
}
