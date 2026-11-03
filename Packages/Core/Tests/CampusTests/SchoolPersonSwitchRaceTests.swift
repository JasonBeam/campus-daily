import XCTest
@testable import Core
import CoreTestSupport

/// Someone else signs in while a school call for the previous person is in flight: whatever
/// that call returns afterwards is dropped, so the previous person's dorm or meter is never
/// written into the new person's account.
final class SchoolPersonSwitchRaceTests: XCTestCase {
    /// Holds the first request whose path ends in `suffix` (and whose body matches) without
    /// blocking the stub's loading thread, so the next person's sign-in can go through meanwhile.
    final class Hold: HTTPClient, @unchecked Sendable {
        // @unchecked: `held` and `waiting` guarded by `lock`.
        let inner: HTTPClient
        let suffix: String
        let body: [String: String]
        let reached: XCTestExpectation
        private let lock = NSLock()
        private var held = false
        private var waiting: CheckedContinuation<Void, Never>?
        private var released = false

        init(_ h: Harness, _ test: XCTestCase, suffix: String, body: [String: String] = [:]) {
            inner = h.server.makeClient(); self.suffix = suffix; self.body = body
            reached = test.expectation(description: "request in flight")
        }

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let fields = request.body.flatMap { try? JSONValue.parse($0) }
            let matches = request.url.path.hasSuffix(suffix) && body.allSatisfy { fields?[$0.key]?.text == $0.value }
            let first = matches && lock.withLock { () -> Bool in defer { held = true }; return !held }
            if first {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    let go = lock.withLock { () -> Bool in
                        if released { return true }
                        waiting = c; return false
                    }
                    reached.fulfill()
                    if go { c.resume() }
                }
            }
            return try await inner.send(request)
        }

        func release() {
            let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                released = true; defer { waiting = nil }; return waiting
            }
            c?.resume()
        }
    }

    func session(_ h: Harness, _ hold: Hold) -> SchoolSession {
        SchoolSession(portal: PortalClient(http: hold), ecykt: EcyktClient(http: hold), vault: h.vault,
                      passwordLogin: h.passwordLogin, now: h.clock.function)
    }

    /// Signed in as a person whose card differs from the one the web sign-in fixture shows.
    func previousPerson(portal: Bool = false) throws -> Harness {
        let h = Harness()
        try h.signedIn(portal: portal)
        var session = T.session(); session.cardUnionID = SchoolAccountSwitchTests.otherCard
        try h.vault.saveEcyktSession(session)
        return h
    }

    /// The next person signs in on the official web page (their card answers the liveness check).
    func signInSomeoneElse(_ session: SchoolSession) async throws {
        let state = try FixtureLoader.csaLoginState()
        let summary = try await session.adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertTrue(summary.switchedAccount)
    }

    /// Someone else's sign-in fails after its writes began (the previous person's items are
    /// gone): it still counts as a change of person, so pages showing the previous person's
    /// data close. One that fails before writing anything does not, and one that succeeds does.
    func testASignInThatFailsAfterItsWritesBeganIsAChangeOfPerson() async throws {
        let h = try previousPerson()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let session = h.session()
        h.store.failWrites(to: .schoolProfile)
        var changes = 0
        do {
            try await SchoolSession.watchingPerson(on: session, { try await self.signInSomeoneElse(session) }, changed: { changes += 1 })
            XCTFail("the sign-in's profile write was meant to fail")
        } catch {
            XCTAssertTrue(error is StorageError, "\(error)")
        }
        XCTAssertEqual(changes, 1, "the wipe began")
    }

    func testASignInThatFailsBeforeWritingIsNoChangeOfPerson() async throws {
        let h = try previousPerson()
        let session = h.session()
        var changes = 0
        do {
            try await SchoolSession.watchingPerson(on: session, { try await self.signInSomeoneElse(session) }, changed: { changes += 1 })
            XCTFail("nothing answers the liveness check")
        } catch {}
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(try h.vault.ecyktSession()?.cardUnionID, SchoolAccountSwitchTests.otherCard, "nothing was written")

        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try await SchoolSession.watchingPerson(on: session, { try await self.signInSomeoneElse(session) }, changed: { changes += 1 })
        XCTAssertEqual(changes, 1, "someone else signed in")
    }

    func testSwitchDuringElectricityMatchWritesNothing() async throws {
        let h = try previousPerson()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = session(h, hold)
        async let result = session.resolveElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await signInSomeoneElse(session)
        hold.release()
        do {
            _ = try await result
            XCTFail("a match for the previous person must not succeed")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.profile(), "no dorm or meter of the previous person")
    }

    /// The match found several same-name rooms (or a room with no meter) for the previous
    /// person: no list and no picker stop reaches the next person, whichever way they signed in.
    func testSwitchWhileSameNamedMetersAreFoundOffersNoChoice() async throws {
        for (sameName, byForm) in [(true, false), (true, true), (false, false)] {
            var h = try previousPerson()
            h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
            if byForm {
                h.server.serve(try T.eCardWithTicket())
                h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "NEXT-TOKEN"))
            }
            try h.server.serve("ecykt/getSysBindCustInfo-ok")
            if sameName {
                MeterWalkTests.level(h, MeterWalkTests.floor.id, [("991", MeterWalkTests.room.id), ("991", "991001001000109000001004")])
                MeterWalkTests.meters(h, "991001001000109000001004", [("000000000994", "99栋991")])
            } else {
                MeterWalkTests.meters(h, MeterWalkTests.room.id, [])
            }
            try SchoolElectricityTests.serveTree(h)
            let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
            let session = session(h, hold)
            async let result = session.resolveElectricity()
            await fulfillment(of: [hold.reached], timeout: 5)
            if byForm {
                let summary = try await session.signIn(account: "99100992", password: "synthetic-pw-992", savePassword: false, owning: .unchecked)
                XCTAssertTrue(summary.switchedAccount)
            } else {
                try await signInSomeoneElse(session)
            }
            hold.release()
            do {
                let late = try await result
                XCTFail("the previous person's match reached the next one: \(late)")
            } catch {
                XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
            }
            XCTAssertNil(try h.vault.profile()?.meter)
        }
    }

    /// The next person's sign-in wipes the previous person's account and tokens, then a later
    /// write of the same step fails (a full Keychain): the sign-in fails, but the previous
    /// person's match still in flight is stale all the same and writes no dorm or meter next to
    /// what is left.
    func testASwitchWhoseWritesFailHalfwayStillDropsThePreviousPersonsMatch() async throws {
        for byForm in [false, true] {
            var h = try previousPerson()
            h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
            if byForm {
                h.server.serve(try T.eCardWithTicket())
                h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "NEXT-TOKEN"))
            }
            try h.server.serve("ecykt/getSysBindCustInfo-ok")
                try SchoolElectricityTests.serveTree(h)
            let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
            let session = session(h, hold)
            let stamp = await session.personStamp()
            async let result = session.resolveElectricity()
            await fulfillment(of: [hold.reached], timeout: 5)
            // The previous person's items go first; the profile write after them fails.
            h.store.failWrites(to: .schoolProfile)
            do {
                if byForm {
                    _ = try await session.signIn(account: "99100992", password: "synthetic-pw-992", savePassword: false, owning: .unchecked)
                } else {
                    try await signInSomeoneElse(session)
                }
                XCTFail("byForm \(byForm): the sign-in's profile write was meant to fail")
            } catch {
                XCTAssertTrue(error is StorageError, "byForm \(byForm): \(error)")
            }
            XCTAssertNil(try h.vault.account(), "byForm \(byForm): the wipe ran")
            let stale = await session.isSamePerson(since: stamp)
            XCTAssertFalse(stale, "byForm \(byForm): the previous person's work is stale once the wipe began")
            h.store.failWrites(to: .schoolProfile, false)
            hold.release()
            do {
                let late = try await result
                XCTFail("byForm \(byForm): the previous person's match was written: \(late)")
            } catch {
                XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt), "byForm \(byForm)")
            }
            XCTAssertNil(try h.vault.profile()?.meter, "byForm \(byForm): no meter of the previous person")
        }
    }

    /// The previous person's match was dropped by the switch: the next person's own match
    /// runs instead, so their first setup is not left without a meter or a word.
    func testAMatchDroppedBySomeoneElsesSignInRunsForThem() async throws {
        let h = try previousPerson()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = session(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await signInSomeoneElse(session)
        let next = await session.personStamp()
        hold.release()
        let (stamp, found) = try await result
        XCTAssertEqual(stamp, next, "the answer is the next person's")
        XCTAssertEqual(found, .noAddress, "their own match: no dorm known for them yet")
        XCTAssertNil(try h.vault.profile()?.meter)
    }

    func testAMatchDroppedBySignOutIsNotRunAgain() async throws {
        let h = try previousPerson()
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = session(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        hold.release()
        do { _ = try await result; XCTFail("signed out") } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.profile())
    }

    /// Signed out while the walk reads a level: no further level or meter is read with the
    /// signed-out card session.
    func testASignOutMidWalkStopsTheReads() async throws {
        let h = try previousPerson()
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getBuildingInfo", "buildingID": MeterWalkTests.campus.id])
        let session = session(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        hold.release()
        do { _ = try await result; XCTFail("signed out") } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        let reads = h.server.requests(path: "/electricnew/service")
        XCTAssertEqual(reads.map { $0.bodyField("buildingID") }, [nil, MeterWalkTests.campus.id], "nothing after the held read")
    }

    /// Someone else signed in while the walk reads a level: the rest of the walk is not read
    /// for the one who left (theirs starts from the top).
    func testAnotherPersonMidWalkStopsTheOldWalksReads() async throws {
        let h = try previousPerson()
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getBuildingInfo", "buildingID": MeterWalkTests.apartment.id])
        let session = session(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        try h.signedIn()
        hold.release()
        _ = try? await result
        let floorsRead = h.server.requests(path: "/electricnew/service").filter { $0.bodyField("buildingID") == MeterWalkTests.building.id }
        XCTAssertEqual(floorsRead.count, 0, "the old walk stopped at the held read")
    }

    /// A sign-out that could not delete the card session is still a sign-out: the dropped
    /// match is not run again on what was left behind.
    func testAMatchDroppedByAFailedSignOutIsNotRunAgain() async throws {
        let h = try previousPerson()
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = session(h, hold)
        async let result = session.matchElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        h.store.failWrites(to: .schoolEcykt)
        do { try await session.signOut(); XCTFail("expected a sign-out failure") } catch is SchoolSession.SignOutFailure {}
        XCTAssertNotNil(try h.vault.ecyktSession(), "the card session could not be deleted")
        hold.release()
        do { _ = try await result; XCTFail("signed out") } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.profile()?.meter, "nothing matched on what the sign-out left")
    }

    /// A same-name list or the manual picker opened for the previous person: the next person's
    /// pick from it is refused, though their own sign-in is current.
    func testAPickFromThePreviousPersonsListSavesNothing() async throws {
        let h = try previousPerson()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let session = h.session()
        let stamp = await session.personStamp()
        try await signInSomeoneElse(session)
        let meter = Meter(comAddress: "000000000991", name: "99栋991")
        let room = PowerNode(id: "991001001000109000001003", name: "991")
        do {
            try await session.chooseMatchedMeter(MeterCandidate(meter: meter, path: [room]), since: stamp)
            XCTFail("a pick from the previous person's list must not be saved")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        do {
            try await session.chooseMeter(nodeID: room.id, meter: meter, since: stamp)
            XCTFail("a pick from the previous person's picker must not be saved")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.profile()?.meter)
        let now = await session.personStamp()
        try await session.chooseMeter(nodeID: room.id, meter: meter, since: now)
        XCTAssertEqual(try h.vault.profile()?.meter?.comAddress, "000000000991", "their own pick is kept")
    }

    func testSwitchWhileReadingTheDormWritesNothing() async throws {
        let h = try previousPerson(portal: true)
        try h.vault.saveProfile(nil)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("portal/getMyInfo-ok")
        let hold = Hold(h, self, suffix: "/getMyInfo")
        let session = session(h, hold)
        async let result = session.resolveElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await signInSomeoneElse(session)
        hold.release()
        do { _ = try await result; XCTFail("expected the late dorm to be dropped") } catch {}
        XCTAssertNil(try h.vault.profile())
    }

    /// A same-name choice offered to the previous person, saved after someone else signed in:
    /// dropped (the save reads nothing from the school, so there is no read to race).
    func testAChosenMeterSavedAfterASwitchWritesNothing() async throws {
        let h = try previousPerson()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let session = h.session()
        let stamp = await session.personStamp()
        try await signInSomeoneElse(session)
        do { try await session.chooseMatchedMeter(MeterCandidate(meter: Meter(comAddress: "000000000991", name: "99栋991"), path: [MeterWalkTests.campus, MeterWalkTests.apartment, MeterWalkTests.building, MeterWalkTests.floor, MeterWalkTests.room]), since: stamp); XCTFail("expected the late choice to be dropped") } catch {}
        XCTAssertNil(try h.vault.profile()?.meter)
        XCTAssertFalse(h.server.requests.contains { $0.url.path.hasSuffix("/electricnew/service") })
    }

    /// The hot-water binding is saved by the app after the user picks a controller, long after
    /// `showerHandoff()` returned the previous person's identity: the stamp taken before the
    /// hand-off tells whether that identity still belongs to whoever is signed in.
    func testPersonStampChangesWhenSomeoneElseSignsIn() async throws {
        let h = try previousPerson()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let session = h.session()
        let stamp = await session.personStamp()
        try await signInSomeoneElse(session)
        let afterSwitch = await session.isSamePerson(since: stamp)
        XCTAssertFalse(afterSwitch, "a binding from the previous person's hand-off must not be saved")
        let again = await session.personStamp()
        try await session.signOut()
        let afterSignOut = await session.isSamePerson(since: again)
        XCTAssertFalse(afterSignOut)
    }

    func testPersonStampStaysWhenTheSamePersonSignsInAgain() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let session = h.session()
        let stamp = await session.personStamp()
        let state = try FixtureLoader.csaLoginState()
        let summary = try await session.adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertFalse(summary.switchedAccount)
        let same = await session.isSamePerson(since: stamp)
        XCTAssertTrue(same)
    }
}
