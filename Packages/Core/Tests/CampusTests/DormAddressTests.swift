import XCTest
import Core

final class DormAddressTests: XCTestCase {
    func testParsesPortalAddressWithUnit() throws {
        let a = try XCTUnwrap(DormAddress.parse("星湖校区99栋9号1层991房"))
        XCTAssertEqual(a, DormAddress(campus: "星湖校区", building: "99", unit: "9", floor: 1, room: "991"))
        XCTAssertEqual(a.meterName, "99栋991")
        XCTAssertEqual(a.chineseFloorLabel, "一楼")
    }

    func testParsesVariants() throws {
        XCTAssertEqual(DormAddress.parse("示例校区 2栋 5层 504房")?.unit, nil)
        XCTAssertEqual(DormAddress.parse("示例校区2幢3号5楼504室")?.room, "504")
        XCTAssertEqual(DormAddress.parse("示例校区A3栋3号12层1201房")?.building, "A3")
        for bad in ["", "2504", "99栋991", "暂无宿舍", "示例校区2栋3号5层", "示例校区2栋3号0层504房"] {
            XCTAssertNil(DormAddress.parse(bad), bad)
        }
    }

    func testFloorMapsToChineseNumerals() throws {
        let expected = ["一楼", "二楼", "三楼", "四楼", "五楼", "六楼", "七楼"]
        for (i, label) in expected.enumerated() {
            let a = try XCTUnwrap(DormAddress.parse("示例校区99栋9号\(i + 1)层991房"))
            XCTAssertEqual(a.chineseFloorLabel, label)
            XCTAssertTrue(a.matchesFloor(label))
            XCTAssertTrue(a.matchesFloor("\(i + 1)楼"))
        }
        XCTAssertEqual(DormAddress.chineseNumeral(10), "十")
        XCTAssertEqual(DormAddress.chineseNumeral(12), "十二")
        XCTAssertEqual(DormAddress.chineseNumeral(20), "二十")
        XCTAssertEqual(DormAddress.chineseNumeral(23), "二十三")
    }

    func testMatchers() throws {
        let a = try XCTUnwrap(DormAddress.parse("星湖校区99栋9号1层991房"))
        XCTAssertTrue(a.matchesCampus("星湖校区"))
        XCTAssertTrue(a.matchesBuilding("99栋"))
        XCTAssertFalse(a.matchesBuilding("199栋"))
        XCTAssertTrue(a.matchesRoom("991"))
        XCTAssertFalse(a.matchesRoom("9910"))
        XCTAssertTrue(a.matchesMeterName("99栋991"))
        XCTAssertTrue(a.matchesMeterName("99栋 · 991"))
        XCTAssertFalse(a.matchesMeterName("199栋991"))
        XCTAssertFalse(a.matchesMeterName("99栋9910"))
        XCTAssertFalse(a.matchesFloor("十一楼"))
    }
}
