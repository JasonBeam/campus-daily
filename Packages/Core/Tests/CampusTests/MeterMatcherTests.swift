import XCTest
import Core

final class MeterMatcherTests: XCTestCase {
    func testMatchOneNoneMany() throws {
        let a = try XCTUnwrap(DormAddress.parse("星湖校区99栋9号1层991房"))
        let m1 = Meter(comAddress: "1", name: "99栋991"), m2 = Meter(comAddress: "2", name: "99栋990"), m3 = Meter(comAddress: "3", name: "99栋991")
        XCTAssertEqual(MeterMatcher.match([m1, m2], address: a), .one(m1))
        XCTAssertEqual(MeterMatcher.match([m2], address: a), .none)
        XCTAssertEqual(MeterMatcher.match([m1, m2, m3], address: a), .many([m1, m3]))
        let binding = MeterBinding(nodeID: "n", comAddress: "3", label: "", nodeIsRoom: true)
        XCTAssertEqual(MeterMatcher.pick([m1, m3], binding: binding), m3)
        XCTAssertNil(MeterMatcher.pick([m1], binding: binding))
    }

    /// A meter replaced in the bound room: the room node's only row, under the room's name.
    func testPickFindsTheReplacedMeterOfTheBoundRoomOnly() {
        let binding = MeterBinding(nodeID: "n", comAddress: "000000000991", label: "99栋 991", nodeIsRoom: true)
        let replaced = Meter(comAddress: "000000000992", name: "99栋991")
        XCTAssertEqual(MeterMatcher.pick([replaced], binding: binding), replaced)
        XCTAssertEqual(MeterMatcher.pick([Meter(comAddress: "000000000992", name: "99栋 · 991房")], binding: binding)?.comAddress,
                       "000000000992")
        var picked = binding; picked.label = "99栋991"
        XCTAssertEqual(MeterMatcher.pick([replaced], binding: picked), replaced, "a meter picked by hand keeps the row's name")
        XCTAssertNil(MeterMatcher.pick([Meter(comAddress: "000000000992", name: "99栋990")], binding: binding), "another room's meter")
        XCTAssertNil(MeterMatcher.pick([replaced, Meter(comAddress: "000000000993", name: "99栋991")], binding: binding),
                     "several rows: nothing tells which one")
        XCTAssertNil(MeterMatcher.pick([], binding: binding))
        var unnamed = binding; unnamed.label = ""
        XCTAssertNil(MeterMatcher.pick([Meter(comAddress: "000000000992", name: "")], binding: unnamed))
    }
}
