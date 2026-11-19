import XCTest
@testable import Core

final class PowerLocationTests: XCTestCase {
    func testPickerPathLeavesOutTheFloor() {
        XCTAssertEqual(PowerLocation.label(["星湖校区", "半山公寓", "99栋", "1楼", "991"]), "星湖校区 · 半山公寓 · 99栋 · 991")
        XCTAssertEqual(PowerLocation.label(["北校区", "3号楼", "十二层", "1208"]), "北校区 · 3号楼 · 1208", "「3号楼」 is a building")
        XCTAssertEqual(PowerLocation.label(["北校区", " ", "3栋", "108"]), "北校区 · 3栋 · 108")
    }

    func testDormUsesTheMeterLocationOnlyForTheSameRoom() {
        var profile = SchoolProfile(residence: PortalResidence(raw: "星湖校区99栋9号1层991房"))
        XCTAssertEqual(profile.dormLocation, "星湖校区 · 99栋 · 991", "no meter: the portal address")
        XCTAssertNil(profile.meterLocation)

        profile.meter = MeterBinding(nodeID: "r", comAddress: "1", label: "99栋 991", nodeIsRoom: true,
                                     location: "星湖校区 · 樱花公寓 · 99栋 · 991")
        XCTAssertEqual(profile.dormLocation, "星湖校区 · 樱花公寓 · 99栋 · 991", "same room: the apartment comes from the meter")
        XCTAssertEqual(profile.meterLocation, "星湖校区 · 樱花公寓 · 99栋 · 991")

        profile.meter?.location = "星湖校区 · 樱花公寓 · 98栋 · 991"
        XCTAssertEqual(profile.dormLocation, "星湖校区 · 99栋 · 991", "meter bound elsewhere: not mixed into the dorm")
        XCTAssertEqual(profile.meterLocation, "星湖校区 · 樱花公寓 · 98栋 · 991")
    }

    func testDirectoryDormLocationOnlyFromTheDirectoryPath() {
        var profile = SchoolProfile(residence: PortalResidence(raw: "星湖校区99栋9号1层991房"))
        XCTAssertNil(profile.directoryDormLocation, "no meter: the portal address is not a full path")

        profile.meter = MeterBinding(nodeID: "c", comAddress: "1", label: "99栋 991", nodeIsRoom: false,
                                     location: "星湖校区 · 99栋991")
        XCTAssertNil(profile.directoryDormLocation, "campus-wide binding: only the campus is known")

        profile.meter = MeterBinding(nodeID: "r", comAddress: "1", label: "99栋 991", nodeIsRoom: true,
                                     location: "星湖校区 · 樱花公寓 · 99栋 · 991")
        XCTAssertEqual(profile.directoryDormLocation, "星湖校区 · 樱花公寓 · 99栋 · 991")

        profile.meter?.location = "星湖校区 · 樱花公寓 · 98栋 · 991"
        XCTAssertNil(profile.directoryDormLocation, "another room's meter")
    }

    func testOldBindingsAndUnreadableDorms() throws {
        // A binding saved before the location was kept decodes and shows its label.
        let old = #"{"nodeID":"r","comAddress":"1","label":"99栋 991","nodeIsRoom":true}"#
        let binding = try JSONDecoder().decode(MeterBinding.self, from: Data(old.utf8))
        XCTAssertNil(binding.location)
        let profile = SchoolProfile(residence: PortalResidence(raw: "暂无宿舍"), meter: binding)
        XCTAssertEqual(profile.meterLocation, "99栋 991")
        XCTAssertNil(profile.dormLocation)
    }
}
