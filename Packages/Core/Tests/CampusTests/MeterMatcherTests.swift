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
}
