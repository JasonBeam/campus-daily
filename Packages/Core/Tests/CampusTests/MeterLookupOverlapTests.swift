import XCTest
@testable import Core
import CoreTestSupport

/// The automatic meter lookup can take minutes on a slow school; meanwhile the same person
/// keeps using the app. What they did in between wins over what the lookup found.
final class MeterLookupOverlapTests: XCTestCase {
    typealias Hold = SchoolPersonSwitchRaceTests.Hold
    typealias Waits = MeterLookupRetryTests.Waits
    typealias SessionBox = MeterLookupRetryTests.SessionBox

    static let picked = MeterBinding(nodeID: "991001009", comAddress: "000000000999", label: "99栋999", nodeIsRoom: true,
                                     location: "星湖校区 · 半山公寓 · 99栋 · 999")

    static func pickByHand(_ session: SchoolSession) async throws {
        try await session.chooseMeter(nodeID: Self.picked.nodeID, meter: Meter(comAddress: Self.picked.comAddress, name: "99栋999"),
                                      path: ["星湖校区", "半山公寓", "99栋", "999"],
                                      since: await session.personStamp())
    }

    func held(_ h: Harness, _ hold: Hold) -> SchoolSession {
        SchoolSession(portal: PortalClient(http: hold), ecykt: EcyktClient(http: hold), vault: h.vault,
                      passwordLogin: h.passwordLogin, now: h.clock.function, meterRetryWait: h.meterRetryWait)
    }

    // MARK: A meter picked by hand

    /// The lookup timed out, and while it waited to try again the user picked the meter in
    /// 「电表」: the retry that then finds the dorm's meter leaves the pick alone.
    func testAPickMadeWhileTheLookupWaitsStays() async throws {
        let box = SessionBox()
        var h = Harness()
        h.meterRetryWait = { _ in try? await Self.pickByHand(box.session!) }
        try h.signedIn()
        h.server.fail("POST", MeterLookupRetryTests.service, bodyMatch: MeterLookupRetryTests.campusRead, with: .timedOut, times: 1)
        try SchoolElectricityTests.serveTree(h)
        let session = h.session()
        box.session = session
        let (_, found) = try await session.matchElectricity()
        XCTAssertEqual(try h.vault.profile()?.meter, Self.picked, "the pick stays")
        XCTAssertEqual(found, .alreadyBound(Self.picked))
    }

    /// Picked while the room's meter was still being read: the same.
    func testAPickMadeDuringTheReadStays() async throws {
        let h = Harness()
        try h.signedIn()
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = held(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await Self.pickByHand(session)
        hold.release()
        let (_, found) = try await result
        XCTAssertEqual(try h.vault.profile()?.meter, Self.picked)
        XCTAssertEqual(found, .alreadyBound(Self.picked))
    }

    /// Same-name rooms found after the user picked one: no list to choose from again.
    func testNoSameNameListOnceAMeterIsPicked() async throws {
        let h = Harness()
        try h.signedIn()
        MeterWalkTests.level(h, MeterWalkTests.floor.id, [("991", MeterWalkTests.room.id), ("991", "991001001000109000001004")])
        MeterWalkTests.meters(h, "991001001000109000001004", [("000000000994", "99栋991")])
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = held(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await Self.pickByHand(session)
        hold.release()
        let (_, found) = try await result
        if case .chooseAmong = found { XCTFail("a list was offered after the pick") }
        XCTAssertEqual(found, .alreadyBound(Self.picked))
        XCTAssertEqual(try h.vault.profile()?.meter, Self.picked)
    }

    // MARK: Same person, another dorm

    static let newDorm = "星湖校区98栋8号1层881房"

    /// 99栋 in 半山公寓 (room 991) and 98栋 in 樱花公寓 (room 881), each with its meter.
    func serveBothDorms(_ h: Harness, oldRoomMeter: Bool = true) throws {
        MeterWalkTests.level(h, "991001002", [("98栋", "991001002000108")])
        MeterWalkTests.level(h, "991001002000108", [("1楼", "991001002000108000001")])
        MeterWalkTests.level(h, "991001002000108000001", [("881", "991001002000108000001001")])
        MeterWalkTests.meters(h, "991001002000108000001001", [("000000000881", "98栋881")])
        if !oldRoomMeter { MeterWalkTests.meters(h, MeterWalkTests.room.id, []) }
        try SchoolElectricityTests.serveTree(h)
    }

    /// The same person signs in again while the lookup runs and the school now shows another
    /// dorm (what such a sign-in leaves: the new dorm, no meter). The late answer for the old
    /// dorm is dropped: the new dorm stays, and its own meter is looked up and bound.
    func testANewDormDuringTheLookupGetsTheNewDormsMeter() async throws {
        let h = Harness()
        try h.signedIn()
        try serveBothDorms(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = held(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try h.vault.saveProfile(SchoolProfile(residence: PortalResidence(raw: Self.newDorm)))
        hold.release()
        let (stamp, found) = try await result
        let profile = try h.vault.profile()
        XCTAssertEqual(profile?.residence?.raw, Self.newDorm, "the new dorm stays")
        XCTAssertEqual(profile?.meter?.comAddress, "000000000881", "the new dorm's meter")
        guard case .matched(let binding, _) = found else { return XCTFail("\(found)") }
        XCTAssertEqual(binding.comAddress, "000000000881")
        let current = await session.personStamp()
        XCTAssertEqual(stamp, current, "still the same person")
    }

    /// The same, where the old dorm's meter was not found: no hint about the old dorm, the new
    /// one's lookup answers.
    func testANewDormDuringALookupThatFoundNothingIsLookedUp() async throws {
        let h = Harness()
        try h.signedIn()
        try serveBothDorms(h, oldRoomMeter: false)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = held(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try h.vault.saveProfile(SchoolProfile(residence: PortalResidence(raw: Self.newDorm)))
        hold.release()
        let (_, found) = try await result
        if case .stopped = found { XCTFail("the old dorm's 'not found'") }
        XCTAssertEqual(try h.vault.profile()?.meter?.comAddress, "000000000881")
        XCTAssertEqual(try h.vault.profile()?.residence?.raw, Self.newDorm)
    }
}
