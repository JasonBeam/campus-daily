import XCTest
@testable import Core

/// Same-named rooms are listed under the first location level that tells them apart.
final class LocationNamingTests: XCTestCase {
    func testTheApartmentTitlesRoomsThatDifferByApartment() {
        let titles = LocationNaming.titles(locations: ["北校区 · 东苑公寓 · 3 栋 · 108", "北校区 · 西苑公寓 · 3 栋 · 108"])
        XCTAssertEqual(titles, ["东苑公寓", "西苑公寓"])
    }

    func testTheCampusTitlesRoomsThatDifferByCampus() {
        let titles = LocationNaming.titles(locations: ["北校区 · 东苑公寓 · 3 栋 · 108", "南校区 · 东苑公寓 · 3 栋 · 108",
                                                       "南校区 · 西苑公寓 · 3 栋 · 108"])
        XCTAssertEqual(titles, ["北校区", "南校区", "南校区"])
    }

    func testIdenticalOrShorterPathsFallBackSensibly() {
        XCTAssertEqual(LocationNaming.titles(locations: ["北校区 · 3 栋 · 108"]), ["108"])
        XCTAssertEqual(LocationNaming.titles(locations: ["北校区 · 东苑公寓", "北校区"]), ["东苑公寓", "北校区"])
    }

    func testTheHintCountsTheRooms() {
        XCTAssertEqual(LocationNaming.sameNameHint(count: 2, name: "3 栋 108"), "学校有 2 间都叫 3 栋 108，选你住的那间。")
    }
}
