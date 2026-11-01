import XCTest
@testable import Core
import CoreTestSupport

/// The automatic meter lookup walks the picker's own levels (校区 → 公寓 → 楼栋 → 楼层 → 房间),
/// one small read each, matching the dorm address. All matched: the room's meter is bound.
/// Otherwise it stops at the level that did not match exactly once, with the levels above kept.
final class MeterWalkTests: XCTestCase {
    static let service = "https://ecykt.gdbtu.edu.cn/ykt-mini/api/electricnew/service"
    static let campus = PowerNode(id: "991001", name: "星湖校区")
    static let apartment = PowerNode(id: "991001001", name: "半山公寓")
    static let building = PowerNode(id: "991001001000109", name: "99栋")
    static let floor = PowerNode(id: "991001001000109000001", name: "1楼")
    static let room = PowerNode(id: "991001001000109000001003", name: "991")

    /// One level of a synthetic tree (`parent` nil = the campuses).
    static func level(_ h: Harness, _ parent: String?, _ children: [(String, String)]) {
        let rows = children.map { #"{\"buildingName\":\"\#($0.0)\",\"buildingID\":\"\#($0.1)\"}"# }.joined(separator: ",")
        h.server.respond("POST", service, bodyMatch: ["server": "/api/getBuildingInfo", "buildingID": parent],
                         body: Data(#"{"code":0,"msg":"获取成功","data":"[\#(rows)]"}"#.utf8))
    }

    /// One node's meters: (comAddress, piplineName).
    static func meters(_ h: Harness, _ node: String, _ rows: [(String, String)]) {
        let list = rows.map { #"{\"comAddress\":\"\#($0.0)\",\"piplineName\":\"\#($0.1)\",\"leftMoney\":\"12.00\"}"# }.joined(separator: ",")
        h.server.respond("POST", service, bodyMatch: ["server": "/api/getMeterStatus", "buildingID": node],
                         body: Data(#"{"code":0,"msg":"获取成功","data":"[\#(list)]"}"#.utf8))
    }

    /// The campus-wide meter list is still served: a lookup that asked for it would find it.
    static func serveCampusList(_ h: Harness) throws {
        h.server.serve(try SchoolElectricityTests.campusMeters(extra: ["99栋991"]), matchBody: ["server", "buildingID"])
    }

    static func campusWideReads(_ h: Harness) -> Int {
        h.server.requests(path: "/electricnew/service").filter {
            $0.bodyField("server") == "/api/getMeterStatus" && $0.bodyField("buildingID") == campus.id
        }.count
    }

    func stopped(_ h: Harness, file: StaticString = #filePath, line: UInt = #line) async throws -> MeterWalkStop {
        let result = try await h.session().resolveElectricity()
        guard case .stopped(let stop) = result else {
            XCTFail("\(result)", file: file, line: line)
            throw CancellationError()
        }
        XCTAssertNil(try h.vault.profile()?.meter, "nothing bound", file: file, line: line)
        XCTAssertEqual(Self.campusWideReads(h), 0, "never the campus-wide list", file: file, line: line)
        return stop
    }

    // MARK: Every level matched

    func testEveryLevelMatchedBindsTheRoomsMeterWithSmallReadsOnly() async throws {
        let h = Harness()
        try h.signedIn()
        try Self.serveCampusList(h)
        try SchoolElectricityTests.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .matched(let binding, let meter) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(binding, MeterBinding(nodeID: Self.room.id, comAddress: "000000000991", label: "99栋 991", nodeIsRoom: true,
                                             location: "星湖校区 · 半山公寓 · 99栋 · 991"))
        XCTAssertEqual(meter.leftMoney, Money(fen: 3692))
        XCTAssertEqual(try h.vault.profile()?.meter, binding)
        XCTAssertEqual(Self.campusWideReads(h), 0)
        let meterReads = h.server.requests(path: "/electricnew/service").filter { $0.bodyField("server") == "/api/getMeterStatus" }
        XCTAssertEqual(meterReads.map { $0.bodyField("buildingID") }, [Self.room.id], "only the room's own row")
        XCTAssertTrue(h.server.requests.allSatisfy { $0.timeout == URLSessionHTTPClient.requestTimeout }, "every read keeps the client's wait")
        XCTAssertTrue(h.server.unmatched.isEmpty)
    }

    /// No apartment level: the campus lists the buildings itself.
    func testACampusListingBuildingsDirectlyIsWalkedToo() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, nil, [("星湖校区", "991001")])
        Self.level(h, "991001", [("98栋", "991001098"), ("99栋", "991001099")])
        Self.level(h, "991001099", [("1层", "991001099001")])
        Self.level(h, "991001099001", [("991", "991001099001991")])
        Self.meters(h, "991001099001991", [("000000000991", "99栋991")])
        let result = try await h.session().resolveElectricity()
        guard case .matched(let binding, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(binding.nodeID, "991001099001991")
        XCTAssertTrue(binding.nodeIsRoom)
        XCTAssertEqual(binding.location, "星湖校区 · 99栋 · 991")
    }

    // MARK: Stopped at a level

    func testNoMatchingCampusStopsAtTheCampuses() async throws {
        let h = Harness()
        try h.signedIn(residence: "示例校区99栋9号1层991房")
        try Self.serveCampusList(h)
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .campus)
        XCTAssertEqual(stop.path, [])
        XCTAssertEqual(stop.options.map(\.id), ["991001", "001002", "001003", "001004"])
        XCTAssertEqual(stop.suggested, [])
    }

    /// The portal names no apartment: the apartment is the one holding the dorm's building.
    func testNoApartmentHoldingTheBuildingStopsAtTheApartments() async throws {
        let h = Harness()
        try h.signedIn(residence: "星湖校区97栋9号1层991房")
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .apartment)
        XCTAssertEqual(stop.path, [Self.campus])
        XCTAssertEqual(stop.options.count, 9)
        XCTAssertEqual(stop.options.first, Self.apartment)
        XCTAssertEqual(stop.suggested, [])
    }

    static let lanxiang = PowerNode(id: "991001007", name: "兰香公寓")
    static let lanxiangRoom = PowerNode(id: "991001007000109000001003", name: "991")

    /// 兰香公寓 holds a 99栋 too, with a 1楼 listing `rooms`; `meter` is 991's row there.
    static func secondNinetyNine(_ h: Harness, rooms: [(String, String)], meter: (String, String)? = nil) {
        level(h, lanxiang.id, [("99栋", "991001007000109")])
        level(h, "991001007000109", [("1楼", "991001007000109000001")])
        level(h, "991001007000109000001", rooms)
        if let meter { meters(h, lanxiangRoom.id, [meter]) }
    }

    /// Two apartments hold a 99栋, only 半山公寓's has room 991: both are walked down to the
    /// rooms and that room's meter is bound without asking.
    func testTwoApartmentsHoldingTheBuildingBindTheOneWithTheRoom() async throws {
        let h = Harness()
        try h.signedIn()
        Self.secondNinetyNine(h, rooms: [("990", "991001007000109000001002"), ("992", "991001007000109000001004")])
        try SchoolElectricityTests.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .matched(let binding, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(binding.nodeID, Self.room.id)
        XCTAssertEqual(binding.location, "星湖校区 · 半山公寓 · 99栋 · 991")
        XCTAssertEqual(try h.vault.profile()?.meter, binding)
        XCTAssertTrue(h.server.requests.contains { $0.bodyField("buildingID") == "991001007000109000001" }, "兰香公寓's rooms were read")
        XCTAssertEqual(Self.campusWideReads(h), 0)
    }

    /// Both apartments' 99栋 have a 991 with a meter: stopped at the apartments, those two
    /// offered as rooms to bind, each with its full location.
    func testTwoApartmentsBothWithTheRoomStopWithBothCandidates() async throws {
        let h = Harness()
        try h.signedIn()
        Self.secondNinetyNine(h, rooms: [("991", Self.lanxiangRoom.id)], meter: ("990000007991", "99栋991"))
        try SchoolElectricityTests.serveTree(h)
        let session = h.session()
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .apartment)
        XCTAssertEqual(stop.path, [Self.campus])
        XCTAssertEqual(stop.suggested, [Self.apartment.id, Self.lanxiang.id])
        XCTAssertEqual(stop.candidates.map(\.room?.id), [Self.room.id, Self.lanxiangRoom.id])
        XCTAssertEqual(stop.candidates.map(\.meter.comAddress), ["000000000991", "990000007991"])
        XCTAssertEqual(stop.candidates.map(\.location), ["星湖校区 · 半山公寓 · 99栋 · 991", "星湖校区 · 兰香公寓 · 99栋 · 991"])
        XCTAssertEqual(stop.candidates.map(stop.branchName), ["半山公寓", "兰香公寓"])

        try await session.chooseMatchedMeter(stop.candidates[1], since: await session.personStamp())
        XCTAssertEqual(try h.vault.profile()?.meter?.nodeID, Self.lanxiangRoom.id)
        XCTAssertEqual(try h.vault.profile()?.meter?.location, "星湖校区 · 兰香公寓 · 99栋 · 991")
    }

    /// Neither apartment's 99栋 has the room: stopped at the apartments as before, both
    /// suggested, nothing to bind offered.
    func testTwoApartmentsNeitherWithTheRoomStopWithoutCandidates() async throws {
        let h = Harness()
        try h.signedIn(residence: "星湖校区99栋9号1层998房")
        Self.secondNinetyNine(h, rooms: [("990", "991001007000109000001002")])
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .apartment)
        XCTAssertEqual(stop.path, [Self.campus])
        XCTAssertEqual(stop.options.count, 9)
        XCTAssertEqual(stop.suggested, [Self.apartment.id, Self.lanxiang.id])
        XCTAssertEqual(stop.candidates, [])
    }

    // MARK: Branches that halted before the rooms

    /// 半山公寓's 99栋 names its floors in a way not matched (stopped at 选楼层), 兰香公寓's has
    /// 991: 半山公寓 is not taken for one without the room. Nothing bound; stopped at the
    /// apartments with 半山公寓 to choose where it halted and 兰香公寓's room to bind.
    func testAnApartmentHaltedAtItsFloorsIsNotTakenForOneWithoutTheRoom() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, Self.building.id, [("A区", "991001001000109000091"), ("B区", "991001001000109000092")])
        Self.secondNinetyNine(h, rooms: [("991", Self.lanxiangRoom.id)], meter: ("990000007991", "99栋991"))
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .apartment)
        XCTAssertEqual(stop.path, [Self.campus])
        XCTAssertEqual(stop.suggested, [Self.apartment.id, Self.lanxiang.id])
        XCTAssertEqual(stop.candidates.map(\.room?.id), [Self.lanxiangRoom.id])
        XCTAssertEqual(stop.halted.map(\.level), [.floor])
        XCTAssertEqual(stop.halted.first?.path, [Self.campus, Self.apartment, Self.building])
        XCTAssertEqual(stop.halted.first?.options.map(\.name), ["A区", "B区"])
        let q = try XCTUnwrap(MeterQuestion(stop, address: DormAddress.parse("星湖校区99栋9号1层991房")))
        XCTAssertEqual(q.text, "99 栋 991 在哪个公寓？")
        XCTAssertEqual(q.rows.map(\.title), ["半山公寓", "兰香公寓"])
        XCTAssertEqual(q.rows.map(\.location), ["这边没对上，点进去自己选", "星湖校区 · 兰香公寓 · 99栋 · 991"])
        XCTAssertEqual(q.rows.first?.picker, stop.halted.first)
        XCTAssertNil(q.rows.first?.candidate)
        XCTAssertEqual(q.rows.last?.candidate, stop.candidates.first)
    }

    /// Two buildings of the dorm's name inside 半山公寓 (stopped at 选楼栋): halted, not "no room".
    func testAnApartmentHaltedAtItsBuildingsIsOffered() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, Self.apartment.id, [("99栋", Self.building.id), ("99幢", "991001001000199")])
        Self.secondNinetyNine(h, rooms: [("991", Self.lanxiangRoom.id)], meter: ("990000007991", "99栋991"))
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .apartment)
        XCTAssertEqual(stop.candidates.map(\.room?.id), [Self.lanxiangRoom.id])
        XCTAssertEqual(stop.halted.map(\.level), [.building])
        XCTAssertEqual(stop.halted.first?.suggested, [Self.building.id, "991001001000199"])
    }

    /// More same-name rooms in 半山公寓 than are read (stopped at 选房间): halted too.
    func testAnApartmentWithTooManySameNameRoomsIsOffered() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, Self.floor.id, (1...9).map { ("991", "99100100100010900000100\($0)") })
        Self.secondNinetyNine(h, rooms: [("991", Self.lanxiangRoom.id)], meter: ("990000007991", "99栋991"))
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.candidates.map(\.room?.id), [Self.lanxiangRoom.id])
        XCTAssertEqual(stop.halted.map(\.level), [.room])
        XCTAssertEqual(stop.halted.first?.suggested.count, 9)
    }

    /// The only apartment left halted, the other read without the room: the page opens where it
    /// halted (nothing else to choose from).
    func testTheOnlyHaltedApartmentOpensWhereItHalted() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, Self.building.id, [("A区", "991001001000109000091"), ("B区", "991001001000109000092")])
        Self.secondNinetyNine(h, rooms: [("990", "991001007000109000001002")])
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .floor)
        XCTAssertEqual(stop.path, [Self.campus, Self.apartment, Self.building])
        XCTAssertEqual(stop.halted, [])
    }

    /// 兰香公寓's 991 reports no meter: read to the room, so it counts as without it; 半山公寓's
    /// room is bound.
    func testARoomWithoutAMeterCountsAsWithoutTheRoom() async throws {
        let h = Harness()
        try h.signedIn()
        Self.secondNinetyNine(h, rooms: [("991", Self.lanxiangRoom.id)])
        Self.meters(h, Self.lanxiangRoom.id, [])
        try SchoolElectricityTests.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .matched(let binding, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(binding.nodeID, Self.room.id)
    }

    /// A read down the second apartment times out once: it is tried again on its own, and the
    /// walk still ends with both candidates.
    func testAReadDownAnotherApartmentIsTriedAgain() async throws {
        let waits = MeterLookupRetryTests.Waits()
        var h = Harness()
        h.meterRetryWait = { waits.record($0) }
        try h.signedIn()
        h.server.fail("POST", Self.service, bodyMatch: ["server": "/api/getBuildingInfo", "buildingID": "991001007000109000001"],
                      with: .timedOut, times: 1)
        Self.secondNinetyNine(h, rooms: [("991", Self.lanxiangRoom.id)], meter: ("990000007991", "99栋991"))
        try SchoolElectricityTests.serveTree(h)
        let (_, found) = try await h.session().matchElectricity()
        guard case .stopped(let stop) = found else { return XCTFail("\(found)") }
        XCTAssertEqual(stop.candidates.count, 2)
        XCTAssertEqual(waits.asked, [5])
    }

    /// One apartment's reads fail for good (slow school, no connection) while the other has the
    /// room: that apartment is not taken for one without it. The lookup ends unfinished at the
    /// apartments, nothing bound, whichever apartment failed.
    func testAnApartmentWhoseReadsFailedIsNotTakenForOneWithoutTheRoom() async throws {
        for (failing, error) in [("991001001000109", URLError.Code.timedOut), ("991001007000109", .timedOut),
                                 ("991001001000109", .notConnectedToInternet), ("991001007000109000001", .notConnectedToInternet)] {
            let waits = MeterLookupRetryTests.Waits()
            var h = Harness()
            h.meterRetryWait = { waits.record($0) }
            try h.signedIn()
            h.server.fail("POST", Self.service, bodyMatch: ["server": "/api/getBuildingInfo", "buildingID": failing], with: error, times: 3)
            Self.secondNinetyNine(h, rooms: [("991", Self.lanxiangRoom.id)], meter: ("990000007991", "99栋991"))
            try SchoolElectricityTests.serveTree(h)
            let (_, found) = try await h.session().matchElectricity()
            guard case .unfinished(let at) = found else { XCTFail("\(failing) \(error): \(found)"); continue }
            XCTAssertEqual(at.level, .apartment, failing)
            XCTAssertEqual(at.path, [Self.campus], "the matched levels, for the page's path card")
            XCTAssertEqual(at.options.count, 9)
            XCTAssertEqual(at.candidates, [])
            XCTAssertNil(try h.vault.profile()?.meter, failing)
            XCTAssertEqual(waits.asked, [5, 20], failing)
        }
    }

    /// A fully read apartment without the room still counts as none: the other one is bound.
    /// Without several apartments to tell apart, a failed read ends the lookup as the failure.
    func testOnlyASplitEndsUnfinished() async throws {
        var h = Harness()
        h.meterRetryWait = { _ in }
        try h.signedIn()
        h.server.fail("POST", Self.service, bodyMatch: ["server": "/api/getBuildingInfo", "buildingID": Self.floor.id],
                      with: .timedOut, times: 3)
        try SchoolElectricityTests.serveTree(h)
        do { _ = try await h.session().matchElectricity(); XCTFail("expected timedOut") } catch {
            XCTAssertEqual(error as? ServiceError, .timedOut)
        }
    }

    /// Signed out while the second apartment's rooms are read: no further read goes out and
    /// nothing is bound or offered.
    func testSignOutWhileWalkingAnotherApartmentEndsIt() async throws {
        let h = Harness()
        try h.signedIn()
        Self.secondNinetyNine(h, rooms: [("991", Self.lanxiangRoom.id)], meter: ("990000007991", "99栋991"))
        try SchoolElectricityTests.serveTree(h)
        let hold = SchoolSignOutRaceTests.Hold(h, self, suffix: "/electricnew/service",
                                               body: ["server": "/api/getBuildingInfo", "buildingID": "991001007000109000001"])
        let session = h.session()
        async let result = session.resolveElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        hold.release.signal()
        do {
            _ = try await result
            XCTFail("a walk that ends after sign-out must not answer")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.profile())
        XCTAssertFalse(h.server.requests.contains { $0.bodyField("buildingID") == Self.lanxiangRoom.id }, "its meter is not read")
    }

    /// Two campuses of the dorm's name, each holding the room: stopped at the campuses with
    /// both offered, named by campus.
    func testTwoCampusesBothWithTheRoomStopWithBothCandidates() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, nil, [("星湖校区", "991001"), ("星湖校区", "992001")])
        Self.level(h, "992001", [("99栋", "992001099")])
        Self.level(h, "992001099", [("1楼", "992001099001")])
        Self.level(h, "992001099001", [("991", "992001099001991")])
        Self.meters(h, "992001099001991", [("990000002991", "99栋991")])
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .campus)
        XCTAssertEqual(stop.path, [])
        XCTAssertEqual(stop.candidates.map(\.location), ["星湖校区 · 半山公寓 · 99栋 · 991", "星湖校区 · 99栋 · 991"])
        XCTAssertEqual(stop.candidates.map(stop.branchName), ["星湖校区", "星湖校区"])
    }

    func testTwoMatchingBuildingsStopAtTheBuildings() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, nil, [("星湖校区", "991001")])
        Self.level(h, "991001", [("半山公寓", "991001001")])
        Self.level(h, "991001001", [("99栋", "991001001000109"), ("99幢", "991001001000199")])
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .building)
        XCTAssertEqual(stop.path, [Self.campus, Self.apartment])
        XCTAssertEqual(stop.suggested, ["991001001000109", "991001001000199"])
    }

    /// The campus lists buildings itself and none is the dorm's: stopped at 选楼栋 at once,
    /// none of them read as an apartment.
    func testUnmatchedBuildingsRightUnderTheCampusStopAtTheBuildings() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, nil, [("星湖校区", "991001")])
        Self.level(h, "991001", [("98栋", "991001098"), ("100栋", "991001100"), ("101 栋", "991001101")])
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .building)
        XCTAssertEqual(stop.path, [Self.campus])
        XCTAssertEqual(stop.options.map(\.name), ["98栋", "100栋", "101 栋"])
        XCTAssertEqual(stop.suggested, [])
        XCTAssertEqual(h.server.requests(path: "/electricnew/service").map { $0.bodyField("buildingID") }, [nil, "991001"],
                       "two reads: the campuses and the campus")
    }

    func testNoMatchingFloorStopsAtTheFloors() async throws {
        let h = Harness()
        try h.signedIn(residence: "星湖校区99栋9号7层991房")
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .floor)
        XCTAssertEqual(stop.path, [Self.campus, Self.apartment, Self.building])
        XCTAssertEqual(stop.options.map(\.name), ["1楼", "2楼", "3楼"])
        XCTAssertEqual(stop.suggested, [])
    }

    func testNoMatchingRoomStopsAtTheRooms() async throws {
        let h = Harness()
        try h.signedIn(residence: "星湖校区99栋9号1层998房")
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .room)
        XCTAssertEqual(stop.path, [Self.campus, Self.apartment, Self.building, Self.floor])
        XCTAssertEqual(stop.options.map(\.name), ["989", "990", "991"])
        XCTAssertEqual(stop.suggested, [])
    }

    /// The room is there but reports no meter: stopped at the rooms, the dorm's own suggested.
    func testTheRoomWithoutAMeterStopsAtTheRoomsWithItSuggested() async throws {
        let h = Harness()
        try h.signedIn()
        Self.meters(h, Self.room.id, [])
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .room)
        XCTAssertEqual(stop.path.last, Self.floor)
        XCTAssertEqual(stop.suggested, [Self.room.id])
    }

    // MARK: Rooms without a floor level

    /// The building lists its rooms itself: the room is matched there and its meter bound.
    func testRoomsRightUnderTheBuildingAreMatched() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, Self.building.id, [("990", "991001001000109990"), ("991", "991001001000109991")])
        Self.meters(h, "991001001000109991", [("000000000991", "99栋991")])
        try SchoolElectricityTests.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .matched(let binding, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(binding.nodeID, "991001001000109991")
        XCTAssertEqual(binding.location, "星湖校区 · 半山公寓 · 99栋 · 991")
    }

    /// Floors named by bare numbers, one of them the dorm's room number: that floor is not
    /// taken for the room, even when it reports one meter row of another name. Stopped at the
    /// rooms with it suggested.
    func testABareNumberFloorIsNotTakenForTheRoom() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, Self.building.id, [("990", "991001001000109990"), ("991", "991001001000109991")])
        Self.meters(h, "991001001000109991", [("000000000101", "99栋101")])
        Self.level(h, "991001001000109991", [("101", "991001001000109991101")])
        try SchoolElectricityTests.serveTree(h)
        let stop = try await stopped(h)
        XCTAssertEqual(stop.level, .room)
        XCTAssertEqual(stop.path, [Self.campus, Self.apartment, Self.building])
        XCTAssertEqual(stop.suggested, ["991001001000109991"])
    }

    /// A room (no rows under it) reporting one meter row of another name: that row is its meter.
    func testALeafRoomsOnlyRowIsTakenWhateverItsName() async throws {
        let h = Harness()
        try h.signedIn()
        Self.meters(h, Self.room.id, [("000000000991", "示例表")])
        try SchoolElectricityTests.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .matched(let binding, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(binding.nodeID, Self.room.id)
        XCTAssertEqual(binding.comAddress, "000000000991")
    }

    // MARK: Same-name rooms

    /// Two rooms on the floor carry the dorm's number: the list to choose from, each with its own
    /// room (bound to that room when picked).
    func testSameNameRoomsAreOfferedToChooseFrom() async throws {
        let h = Harness()
        try h.signedIn()
        Self.level(h, Self.floor.id, [("990", "991001001000109000001002"), ("991", Self.room.id), ("991", "991001001000109000001004")])
        Self.meters(h, "991001001000109000001004", [("000000000994", "99栋991")])
        try SchoolElectricityTests.serveTree(h)
        let session = h.session()
        let result = try await session.resolveElectricity()
        guard case .chooseAmong(let list) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(list.map(\.room?.id), [Self.room.id, "991001001000109000001004"])
        XCTAssertEqual(list.map(\.meter.comAddress), ["000000000991", "000000000994"])
        XCTAssertEqual(list.map(\.location), ["星湖校区 · 半山公寓 · 99栋 · 991", "星湖校区 · 半山公寓 · 99栋 · 991"])
        XCTAssertNil(try h.vault.profile()?.meter, "nothing is saved until the user picks")
        XCTAssertEqual(Self.campusWideReads(h), 0)

        try await session.chooseMatchedMeter(list[1], since: await session.personStamp())
        XCTAssertEqual(try h.vault.profile()?.meter?.nodeID, "991001001000109000001004")
        XCTAssertEqual(try h.vault.profile()?.meter?.nodeIsRoom, true)
    }

    // MARK: Slow reads

    /// Each small read is tried again on its own: a floor list timing out twice, then the room's
    /// meter once, still ends bound.
    func testEachSmallReadIsTriedAgainOnItsOwn() async throws {
        let waits = MeterLookupRetryTests.Waits()
        var h = Harness()
        h.meterRetryWait = { waits.record($0) }
        try h.signedIn()
        h.server.fail("POST", Self.service, bodyMatch: ["server": "/api/getBuildingInfo", "buildingID": Self.building.id],
                      with: .timedOut, times: 2)
        h.server.fail("POST", Self.service, bodyMatch: ["server": "/api/getMeterStatus", "buildingID": Self.room.id],
                      with: .notConnectedToInternet, times: 1)
        try SchoolElectricityTests.serveTree(h)
        let (_, found) = try await h.session().matchElectricity()
        guard case .matched(let binding, _) = found else { return XCTFail("\(found)") }
        XCTAssertEqual(binding.nodeID, Self.room.id)
        XCTAssertEqual(waits.asked, [5, 20, 5], "two waits for the floors, one for the room")
        let roots = h.server.requests(path: "/electricnew/service").filter { $0.bodyField("buildingID") == nil }
        XCTAssertEqual(roots.count, 1, "what was read already is not read again")
    }

    /// A small read that times out three times ends the lookup as too slow; nothing is bound.
    func testASmallReadTimingOutThreeTimesEndsIt() async throws {
        let waits = MeterLookupRetryTests.Waits()
        var h = Harness()
        h.meterRetryWait = { waits.record($0) }
        try h.signedIn()
        h.server.fail("POST", Self.service, bodyMatch: ["server": "/api/getBuildingInfo", "buildingID": Self.floor.id],
                      with: .timedOut, times: 3)
        try SchoolElectricityTests.serveTree(h)
        do { _ = try await h.session().matchElectricity(); XCTFail("expected timedOut") } catch {
            XCTAssertEqual(error as? ServiceError, .timedOut)
        }
        XCTAssertEqual(waits.asked, [5, 20])
        XCTAssertNil(try h.vault.profile()?.meter)
        XCTAssertEqual(Self.campusWideReads(h), 0)
    }
}
