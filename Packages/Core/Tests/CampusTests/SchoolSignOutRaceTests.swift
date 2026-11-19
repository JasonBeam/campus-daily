import XCTest
@testable import Core
import CoreTestSupport

/// Signing out while a school call is in flight: whatever that call returns afterwards is
/// dropped, so the previous person's session, dorm or meter never comes back.
final class SchoolSignOutRaceTests: XCTestCase {
    /// Holds the first request whose path ends in `suffix` (and whose body matches) until released.
    final class Hold: @unchecked Sendable {
        // @unchecked: `held` guarded by `lock`.
        let reached: XCTestExpectation
        let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var held = false

        init(_ h: Harness, _ test: XCTestCase, suffix: String, body: [String: String] = [:]) {
            reached = test.expectation(description: "request in flight")
            h.server.gate { [self] r in
                guard r.url.path.hasSuffix(suffix), body.allSatisfy({ r.bodyField($0.key) == $0.value }) else { return }
                let first = lock.withLock { () -> Bool in defer { held = true }; return !held }
                guard first else { return }
                reached.fulfill()
                release.wait()
            }
        }
    }

    func testSignOutDuringElectricityMatchKeepsTheProfileEmpty() async throws {
        let h = Harness()
        try h.signedIn()
        try SchoolElectricityTests.serveTree(h)
        let hold = Hold(h, self, suffix: "/electricnew/service", body: ["server": "/api/getMeterStatus"])
        let session = h.session()
        async let result = session.resolveElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        hold.release.signal()
        do {
            _ = try await result
            XCTFail("a match that ends after sign-out must not succeed")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.profile(), "no dorm or meter written back")
        XCTAssertNil(try h.vault.ecyktSession())
    }

    func testSignOutWhileReadingTheDormKeepsTheProfileEmpty() async throws {
        let h = Harness()
        try h.vault.saveEcyktSession(T.session())
        try h.vault.savePortalToken(PortalToken("PORTAL"))
        try h.server.serve("portal/getMyInfo-ok")
        let hold = Hold(h, self, suffix: "/getMyInfo")
        let session = h.session()
        async let result = session.resolveElectricity()
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        hold.release.signal()
        do { _ = try await result; XCTFail("expected a sign-out error") } catch {}
        XCTAssertNil(try h.vault.profile())
    }

    /// A same-name list offered before a sign-out: a pick from it afterwards saves nothing.
    func testSignOutBeforeAChosenMeterIsSavedKeepsTheProfileEmpty() async throws {
        let h = Harness()
        try h.signedIn()
        let session = h.session()
        let stamp = await session.personStamp()
        try await session.signOut()
        do {
            try await session.chooseMatchedMeter(MeterCandidate(meter: Meter(comAddress: "000000000991", name: "99栋991"), path: [MeterWalkTests.campus, MeterWalkTests.apartment, MeterWalkTests.building, MeterWalkTests.floor, MeterWalkTests.room]), since: stamp)
            XCTFail("expected a sign-out error")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.profile())
        XCTAssertTrue(h.server.requests.isEmpty)
    }

    func testSignOutDuringWebStateAdoptionSavesNothing() async throws {
        let h = Harness()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let state = try FixtureLoader.csaLoginState()
        let data = try state.encoded()
        let hold = Hold(h, self, suffix: "/getSysBindCustInfo")
        let session = h.session()
        async let result = session.adoptWebState(data, owning: .unchecked)
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        hold.release.signal()
        do { _ = try await result; XCTFail("expected a sign-out error") } catch {}
        XCTAssertNil(try h.vault.ecyktSession())
        XCTAssertNil(try h.vault.portalToken())
        XCTAssertNil(try h.vault.profile())
    }

    func testSignOutDuringShowerHandoffWritesNoSession() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getSignData-ok")
        let hold = Hold(h, self, suffix: "/getSysBindCustInfo")
        let session = h.session()
        async let result = session.showerHandoff(owning: .unchecked)
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        hold.release.signal()
        do {
            _ = try await result
            XCTFail("expected a sign-out error")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.ecyktSession())
        XCTAssertTrue(h.server.requests(path: "/getSignData").isEmpty, "no hand-off for a signed-out account")
    }

    func testSignOutDuringRechargeSessionWritesNoSession() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/loginBySysId-mintSeries1")
        let hold = Hold(h, self, suffix: "/loginBySysId")
        let session = h.session()
        async let result = session.rechargeSession(.card, owning: .unchecked)
        await fulfillment(of: [hold.reached], timeout: 5)
        try await session.signOut()
        hold.release.signal()
        do {
            _ = try await result
            XCTFail("expected a sign-out error")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertNil(try h.vault.ecyktSession(), "the minted login is not saved for a signed-out account")
    }
}
