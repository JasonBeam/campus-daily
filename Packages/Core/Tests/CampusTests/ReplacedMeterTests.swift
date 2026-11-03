import XCTest
@testable import Core
import CoreTestSupport

/// The school replaced the meter of the bound room: the room node now lists one row with a new
/// `comAddress`. The refresh reads it and the binding follows it; nothing else is healed.
final class ReplacedMeterTests: XCTestCase {
    /// The bound room's node answering with `rows` (name, comAddress).
    static func roomRows(_ rows: [(String, String)]) throws -> Fixture {
        let f = try FixtureLoader.load("ecykt/electric-getMeterStatus-room")
        return T.editingData(f) { data in
            let list: [JSONValue] = rows.map { name, address in
                .object(["comAddress": .string(address), "piplineName": .string(name), "type": .string("电表"),
                         "leftMoney": .string("20.00"), "remaining": .string("30.00"), "onlineStatus": .string("在线")])
            }
            data = .string(String(decoding: (try? JSONValue.array(list).encoded()) ?? Data(), as: UTF8.self))
        }
    }

    func refresh(_ h: Harness, rows: [(String, String)]) async throws -> SchoolReading {
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        h.server.serve(try Self.roomRows(rows), matchBody: ["server", "buildingID"])
        try h.server.serve("ecykt/card-getRecordList-ok")
        return await h.session().refresh(inBackground: true, owning: .unchecked)
    }

    func testTheReplacedMeterIsReadAndTheBindingFollowsIt() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        let reading = try await refresh(h, rows: [("99栋991", "000000000992")])
        XCTAssertEqual(reading.outcome, .ok)
        XCTAssertEqual(try reading.meter?.get()?.comAddress, "000000000992")
        XCTAssertEqual(try reading.meter?.get()?.leftMoney, Money(fen: 2000))
        XCTAssertEqual(reading.roomLabel, "99栋 991")
        var moved = Harness.roomBinding; moved.comAddress = "000000000992"
        XCTAssertEqual(try h.vault.profile()?.meter, moved, "the room node, label and location stay")
        XCTAssertEqual(try h.vault.profile()?.residence?.raw, "星湖校区99栋9号1层991房")
    }

    /// Another room's meter, several rows or none: no meter, and the binding is left as it was.
    func testAnythingElseIsNoMeterAndTheBindingStays() async throws {
        for rows in [[("99栋990", "000000000990")], [("99栋991", "000000000992"), ("99栋991", "000000000993")], []] {
            let h = Harness()
            try h.signedIn(meter: Harness.roomBinding)
            let reading = try await refresh(h, rows: rows)
            XCTAssertEqual(reading.outcome, .ok)
            XCTAssertEqual(try reading.meter?.get(), .some(nil), "\(rows)")
            XCTAssertEqual(try h.vault.profile()?.meter, Harness.roomBinding, "\(rows)")
        }
    }

    /// The move is a compare-and-write: only the binding the read used is moved. A meter picked
    /// in between (or none, signed out) stays.
    func testOnlyTheBindingJustReadIsMoved() {
        let profile = SchoolProfile(residence: PortalResidence(raw: "星湖校区99栋9号1层991房"), meter: Harness.roomBinding)
        var expected = profile; expected.meter?.comAddress = "000000000992"
        XCTAssertEqual(SchoolSession.withMeterMoved(profile, seen: Harness.roomBinding, to: "000000000992"), expected)
        var picked = profile; picked.meter?.nodeID = "991001001000109000001004"
        XCTAssertNil(SchoolSession.withMeterMoved(picked, seen: Harness.roomBinding, to: "000000000992"), "a meter picked meanwhile stays")
        var none = profile; none.meter = nil
        XCTAssertNil(SchoolSession.withMeterMoved(none, seen: Harness.roomBinding, to: "000000000992"))
        XCTAssertNil(SchoolSession.withMeterMoved(nil, seen: Harness.roomBinding, to: "000000000992"))
        XCTAssertNil(SchoolSession.withMeterMoved(profile, seen: Harness.roomBinding, to: "000000000991"), "nothing to move")
    }
}
