import XCTest
@testable import Core
import CoreTestSupport

/// The automatic meter lookup after a slow or unreachable school: each read tried again twice,
/// waiting longer each time; any other failure, a sign-out or someone else signing in ends it.
final class MeterLookupRetryTests: XCTestCase {
    static let service = "https://ecykt.gdbtu.edu.cn/ykt-mini/api/electricnew/service"
    /// The campus's apartments: one of the lookup's small reads.
    static let campusRead: [String: String?] = ["server": "/api/getBuildingInfo", "buildingID": "991001"]

    /// Records the waits asked for; `then` runs inside each (a sign-out, say).
    final class Waits: @unchecked Sendable {
        private let lock = NSLock()
        private var _asked: [TimeInterval] = []
        var asked: [TimeInterval] { lock.withLock { _asked } }
        func record(_ t: TimeInterval) { lock.withLock { _asked.append(t) } }
    }

    func harness(_ waits: Waits, then: (@Sendable () async -> Void)? = nil) throws -> Harness {
        var h = Harness()
        h.meterRetryWait = { t in waits.record(t); await then?() }
        try h.signedIn()
        return h
    }

    func serveMeters(_ h: Harness) throws {
        try SchoolElectricityTests.serveTree(h)
    }

    func campusReads(_ h: Harness) -> Int {
        h.server.requests(path: "/electricnew/service").filter {
            $0.bodyField("server") == "/api/getBuildingInfo" && $0.bodyField("buildingID") == "991001"
        }.count
    }

    func testTimedOutTwiceThenFound() async throws {
        let waits = Waits()
        let h = try harness(waits)
        h.server.fail("POST", Self.service, bodyMatch: Self.campusRead, with: .timedOut, times: 2)
        try serveMeters(h)
        let (_, found) = try await h.session().matchElectricity()
        guard case .matched = found else { return XCTFail("\(found)") }
        XCTAssertEqual(campusReads(h), 3)
        XCTAssertEqual(waits.asked, SchoolSession.meterRetryDelays)
        XCTAssertEqual(SchoolSession.meterRetryDelays, [5, 20], "two more tries, the second wait longer")
        XCTAssertNotNil(try h.vault.profile()?.meter)
    }

    func testOfflineThreeTimesGivesUp() async throws {
        let waits = Waits()
        let h = try harness(waits)
        h.server.fail("POST", Self.service, bodyMatch: Self.campusRead, with: .notConnectedToInternet, times: 3)
        try serveMeters(h)
        do { _ = try await h.session().matchElectricity(); XCTFail("expected offline") } catch {
            XCTAssertEqual(error as? ServiceError, .offline)
        }
        XCTAssertEqual(campusReads(h), 3, "the first try and two more")
        XCTAssertEqual(waits.asked, [5, 20])
        XCTAssertNil(try h.vault.profile()?.meter)
    }

    func testAnotherFailureIsNotTriedAgain() async throws {
        let waits = Waits()
        let h = try harness(waits)
        h.server.respond("POST", Self.service, bodyMatch: Self.campusRead, body: Data(#"{"code":500,"msg":"缺少参数"}"#.utf8))
        try serveMeters(h)
        do { _ = try await h.session().matchElectricity(); XCTFail("expected badRequest") } catch {
            XCTAssertEqual(error as? ServiceError, .badRequest(.ecykt))
        }
        XCTAssertEqual(campusReads(h), 1)
        XCTAssertEqual(waits.asked, [])
    }

    /// Signed out while waiting: no further read, nothing saved, the failure thrown.
    func testASignOutWhileWaitingEndsIt() async throws {
        let waits = Waits()
        let box = SessionBox()
        let h = try harness(waits) { try? await box.session?.signOut() }
        h.server.fail("POST", Self.service, bodyMatch: Self.campusRead, with: .timedOut, times: 1)
        try serveMeters(h)
        let session = h.session()
        box.session = session
        do { _ = try await session.matchElectricity(); XCTFail("signed out") } catch {}
        XCTAssertEqual(campusReads(h), 1)
        XCTAssertEqual(waits.asked, [5])
        XCTAssertNil(try h.vault.profile())
    }

    /// Someone else signs in on the web page while the lookup waits to try again: the previous
    /// person's lookup is not tried again; the next person's own runs and answers, with their
    /// stamp. Nothing of the previous person's dorm or meter is saved.
    func testSomeoneElseSigningInWhileWaitingGetsTheirOwnLookup() async throws {
        let waits = Waits()
        let box = SessionBox()
        let h = try harness(waits) {
            guard let session = box.session,
                  let state = try? FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"],
                  let data = try? state.encoded() else { return }
            _ = try? await session.adoptWebState(data, owning: .unchecked)
        }
        var card = T.session(); card.cardUnionID = SchoolAccountSwitchTests.otherCard
        try h.vault.saveEcyktSession(card)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        h.server.fail("POST", Self.service, bodyMatch: Self.campusRead, with: .timedOut, times: 1)
        try serveMeters(h)
        let session = h.session()
        box.session = session
        let before = await session.personStamp()
        let (stamp, found) = try await session.matchElectricity()
        let now = await session.personStamp()
        XCTAssertNotEqual(now, before, "someone else signed in")
        XCTAssertEqual(stamp, now, "the answer is the next person's")
        XCTAssertEqual(found, .noAddress, "their own lookup: no dorm known for them yet")
        XCTAssertEqual(campusReads(h), 1, "the previous person's read is not tried again")
        XCTAssertEqual(waits.asked, [5])
        XCTAssertNil(try h.vault.profile()?.meter)
        XCTAssertNil(try h.vault.profile()?.residence)
    }

    /// The lookup's task is cancelled while it waits (the app went away): no further read,
    /// nothing saved.
    func testCancelledWhileWaitingEndsIt() async throws {
        let waits = Waits()
        let sentBeforeWaiting = Counter()
        var h = try harness(waits)
        let server = h.server
        h.meterRetryWait = { t in
            waits.record(t)
            sentBeforeWaiting.set(server.requests.count)
            withUnsafeCurrentTask { $0?.cancel() }
        }
        h.server.fail("POST", Self.service, bodyMatch: Self.campusRead, with: .timedOut, times: 1)
        try serveMeters(h)
        do {
            _ = try await h.session().matchElectricity()
            XCTFail("cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(h.server.requests.count, sentBeforeWaiting.value, "nothing sent after the wait")
        XCTAssertEqual(campusReads(h), 1)
        XCTAssertEqual(waits.asked, [5])
        XCTAssertNil(try h.vault.profile()?.meter)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = -1
        var value: Int { lock.withLock { _value } }
        func set(_ v: Int) { lock.withLock { _value = v } }
    }

    final class SessionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _session: SchoolSession?
        var session: SchoolSession? {
            get { lock.withLock { _session } }
            set { lock.withLock { _session = newValue } }
        }
    }
}
