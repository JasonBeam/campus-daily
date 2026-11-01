import XCTest
@testable import Core
import CoreTestSupport

struct Harness {
    let server = StubServer()
    let store = InMemorySecureStore()
    let clock = FakeClock()
    var passwordLogin: SchoolPasswordLogin? = nil
    var diagnostic: @Sendable (String) -> Void = { _ in }
    /// Keep the lifetime lines in `store` as the app and the widget do.
    var keepsCredentialLog = false
    /// False for the widget's session.
    var createsLoginDeviceID = true
    var recordsTimeout = CardActivity.timeout
    /// Runs before the card records request is sent (the stub server's gate would block every request).
    var beforeRecords: (@Sendable () async -> Void)? = nil
    /// The automatic meter lookup's wait before trying again (the app's sleeps).
    var meterRetryWait: @Sendable (TimeInterval) async -> Void = { _ in }
    var vault: StoredSchoolVault { StoredSchoolVault(store: store) }
    var snapshots: SharedSnapshotStore { SharedSnapshotStore(store: store) }

    func session() -> SchoolSession {
        let stub = server.makeClient()
        let http: HTTPClient = beforeRecords.map { HeldRecordsClient(inner: stub, hold: $0) } ?? stub
        return SchoolSession(portal: PortalClient(http: http), ecykt: EcyktClient(http: http), vault: vault,
                             passwordLogin: passwordLogin, now: clock.function, diagnostic: diagnostic,
                             credentialLog: keepsCredentialLog ? CredentialLifetimeLog(store: store) : nil,
                             createsLoginDeviceID: createsLoginDeviceID, recordsTimeout: recordsTimeout,
                             meterRetryWait: meterRetryWait)
    }

    /// The refresher over this harness's session and shared store.
    func refresher() -> SnapshotRefresher {
        SnapshotRefresher(school: session(), store: snapshots)
    }

    func signedIn(portal: Bool = false, meter: MeterBinding? = nil, residence: String = "星湖校区99栋9号1层991房") throws {
        try vault.saveEcyktSession(T.session())
        if portal { try vault.savePortalToken(PortalToken("PORTAL")) }
        try vault.saveProfile(SchoolProfile(residence: PortalResidence(raw: residence), meter: meter))
    }

    static let roomBinding = MeterBinding(nodeID: "991001001000109000001003", comAddress: "000000000991", label: "99栋 991", nodeIsRoom: true)

    func loginBySysIdCalls() -> Int { server.requests(path: "/loginBySysId").count }
    func livenessCalls() -> Int { server.requests(path: "/getSysBindCustInfo").count }
}

final class SchoolRefreshTests: XCTestCase {
    func testRefreshOKReadsBalanceAndRoomMeterWithoutMinting() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
        try h.server.serve("ecykt/card-getRecordList-ok")
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 790))
        XCTAssertEqual(report.snapshot.card.fetchedAt, h.clock.now)
        XCTAssertEqual(report.snapshot.power.value?.leftMoney, Money(fen: 3692))
        XCTAssertEqual(report.snapshot.roomLabel, "99栋 991")
        XCTAssertFalse(report.snapshot.needsLogin)
        XCTAssertTrue(report.snapshotSaved)
        let saved = try XCTUnwrap(try h.snapshots.loadSnapshot())
        XCTAssertEqual(saved.card, report.snapshot.card)
        XCTAssertEqual(saved.power.value?.leftMoney, Money(fen: 3692))
        XCTAssertEqual(saved.activity, report.snapshot.activity)
        // 最近 and the widget keep no voucher: it is for 校园卡记录's list only.
        XCTAssertEqual(report.snapshot.activity.value?.records.isEmpty, false)
        XCTAssertEqual(report.snapshot.activity.value?.records.compactMap(\.voucher), [])
        XCTAssertEqual(h.loginBySysIdCalls(), 0, "refresh never calls loginBySysId")
        XCTAssertTrue(h.server.unmatched.isEmpty)
        // Latest custid ciphertext from the liveness answer is kept for next time.
        XCTAssertEqual(try h.vault.ecyktSession()?.custid, "TESTid00000000000000000000000002")
        // Balance used the custid from the validating response.
        XCTAssertEqual(h.server.requests(path: "/getUserBalance").first?.bodyField("custid"), "TESTid00000000000000000000000002")
    }

    /// Batch 1 acceptance: liveness `-1` → needsLogin while the old balance stays with its fetchedAt.
    func testExpiredLivenessMarksNeedsLoginAndKeepsOldValues() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        let t0 = h.clock.now
        var old = SchoolSnapshotReducer.reduce(.empty, .balance(.success(Money(fen: 790)), at: t0))
        old = SchoolSnapshotReducer.reduce(old, .meter(.success(Meter(comAddress: "000000000991", name: "99栋991")), at: t0))
        try h.snapshots.saveSnapshot(old)
        h.clock.advance(3600)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        try h.server.serve("ecykt/getUserBalance-ok")

        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertTrue(report.snapshot.needsLogin)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 790))
        XCTAssertEqual(report.snapshot.card.fetchedAt, t0)
        XCTAssertEqual(report.snapshot.power.fetchedAt, t0)
        XCTAssertEqual(try h.snapshots.loadSnapshot()?.needsLogin, true)
        XCTAssertFalse(report.reexchanged, "no silent re-exchange in background")
        XCTAssertTrue(h.server.requests(path: "/getUserBalance").isEmpty, "session state is never derived from balance")
    }

    func testForegroundSilentReexchangeOnce() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "REEXCHANGED-TOKEN"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")

        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertTrue(report.reexchanged)
        XCTAssertFalse(report.snapshot.needsLogin)
        let stored = try XCTUnwrap(try h.vault.ecyktSession())
        XCTAssertEqual(stored.token, "REEXCHANGED-TOKEN")
        XCTAssertEqual(stored.syscustid, "SYNTH-SYS-NEW")
        XCTAssertEqual(h.server.requests(path: "/csalogintoken/450010").first?.bodyField("ticket"), "SYNTHETIC-TICKET-1")
        XCTAssertEqual(h.server.requests(path: "/getSysBindCustInfo").last?.header("acc_token"), "REEXCHANGED-TOKEN")
        XCTAssertEqual(h.loginBySysIdCalls(), 0)
    }

    func testReexchangeStillExpiredStopsAfterOneRetry() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "STILL-DEAD"))
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertEqual(h.livenessCalls(), 2)
        XCTAssertEqual(h.server.requests(path: "/getMyECard").count, 1)
        XCTAssertTrue(report.snapshot.needsLogin)
    }

    func testPortalTokenDeadAsksForLogin() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"))
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .needsLogin(.sessionExpired(.portal)))
        XCTAssertTrue(h.server.requests(path: "/csalogintoken/450010").isEmpty)
    }

    func testOfflineLivenessKeepsSessionAndValues() async throws {
        let h = Harness()
        try h.signedIn()
        try h.snapshots.saveSnapshot(SchoolSnapshotReducer.reduce(.empty, .balance(.success(Money(fen: 5)), at: h.clock.now)))
        h.server.fail("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/api/customer/getSysBindCustInfo", with: .notConnectedToInternet)
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .failed(.offline))
        XCTAssertFalse(report.snapshot.needsLogin)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 5))
        XCTAssertEqual(report.snapshot.card.error, .offline)
        XCTAssertNotNil(try h.vault.ecyktSession())
    }

    func testPerTileFailuresAreIndependent() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-missingCustid")
        try h.server.serve("ecykt/electric-getMeterStatus-unknownBuilding")
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertEqual(report.snapshot.card.error, .badRequest(.ecykt))
        XCTAssertTrue(report.snapshot.power.notFound)
        XCTAssertNil(report.snapshot.power.error)
    }

    /// Campus only reports what it read; the shared snapshot is written by the refresher alone.
    func testSchoolSessionNeverWritesTheSharedSnapshot() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
        let reading = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .ok)
        XCTAssertEqual(reading.balance, .success(Money(fen: 790)))
        XCTAssertEqual(reading.roomLabel, "99栋 991")
        XCTAssertEqual(reading.checkedAt, h.clock.now)
        XCTAssertNil(try h.store.read(.sharedSnapshot))
        try await h.session().signOut()
        XCTAssertNil(try h.store.read(.sharedSnapshot))
    }

    func testNotSignedIn() async throws {
        let h = Harness()
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .notSignedIn)
        XCTAssertTrue(h.server.requests.isEmpty)
    }

    /// Signing out while the liveness call is in flight: the late answer never writes the
    /// school card session back, so the next launch is signed out too.
    func testSignOutDuringRefreshIsNotUndone() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
        let reached = expectation(description: "liveness in flight")
        let release = DispatchSemaphore(value: 0)
        h.server.gate { r in
            guard r.url.path.hasSuffix("/getSysBindCustInfo") else { return }
            reached.fulfill()
            release.wait()
        }
        let session = h.session()
        async let reading = session.refresh(inBackground: true, owning: .unchecked)
        await fulfillment(of: [reached], timeout: 5)
        try await session.signOut()
        release.signal()
        let result = await reading
        XCTAssertEqual(result.outcome, .notSignedIn)
        XCTAssertNil(result.balance)
        XCTAssertNil(try h.vault.ecyktSession(), "the session stays signed out")
    }
}

final class SchoolRechargeTests: XCTestCase {
    /// Batch 1 acceptance: the recharge session calls loginBySysId once and uses the fresh token.
    func testCardRechargeSessionUsesFreshToken() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/loginBySysId-mintSeries1")
        let web = try await h.session().rechargeSession(.card, owning: .unchecked)
        XCTAssertEqual(h.loginBySysIdCalls(), 1)
        XCTAssertEqual(h.livenessCalls(), 1)
        XCTAssertEqual(web.startURL, SchoolEndpoints.rechargePage)
        let state = try JSONValue.parse(web.stateJSON)
        XCTAssertEqual(state["logintoken"]?.text, "REDACTED_TOKEN_9")
        XCTAssertNotEqual(state["logintoken"]?.text, "REDACTED_TOKEN_2")
        XCTAssertEqual(state["loginInfo"]?["token"]?.text, "REDACTED_TOKEN_9")
        XCTAssertEqual(state["loginInfo"]?["syscustid"]?.text, "TESTid00000000000000000000000003")
        XCTAssertEqual(state["schoolid"]?.text, "450010")
        XCTAssertEqual(state["custInfo"]?["custunionid"]?.text, "TESTid00000000000000000000000001")
        XCTAssertEqual(state["custid"]?.text, "TESTid00000000000000000000000002")
        XCTAssertTrue(web.userScript.contains("location.origin !== 'https://ecykt.gdbtu.edu.cn'"))
        XCTAssertTrue(web.userScript.contains("elecampus_state"))
        XCTAssertFalse("\(web)".contains("REDACTED_TOKEN_9"))
        XCTAssertEqual(try h.vault.ecyktSession()?.syscustid, "TESTid00000000000000000000000003")
        // Same shape as the official CSA state for the fields the page reads.
        let official = try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"]
        for key in ["logintoken", "loginInfo", "schoolid", "custInfo"] { XCTAssertNotNil(official?[key], key); XCTAssertNotNil(state[key], key) }
    }

    func testElectricityRechargeStartsAtPowerEntry() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/loginBySysId-mintSeries2")
        let web = try await h.session().rechargeSession(.electricity, owning: .unchecked)
        let comps = try XCTUnwrap(URLComponents(url: web.startURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "/ykt-mini/api/electricnew/getPowerUrl")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "syscustid" }?.value, "TESTid00000000000000000000000004")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "custid" }?.value, "TESTid00000000000000000000000002")
    }

    func testExpiredRechargeNeverMints() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        try h.server.serve("ecykt/loginBySysId-mintSeries1")
        await T.expectError(.sessionExpired(.ecykt)) { _ = try await h.session().rechargeSession(.card, owning: .unchecked) }
        XCTAssertEqual(h.loginBySysIdCalls(), 0)
    }

    func testNavigationAllowList() {
        let ecykt = "ecykt.gdbtu.edu.cn"
        XCTAssertEqual(RechargeNavigation.decide(URL(string: "https://ecykt.gdbtu.edu.cn/ykt-view/recharge")!, isUserTap: false, sourceHost: nil), .allow)
        XCTAssertEqual(RechargeNavigation.decide(URL(string: "https://cas.gdbtu.edu.cn/cas/login")!, isUserTap: false, sourceHost: ecykt), .allow)
        XCTAssertEqual(RechargeNavigation.decide(URL(string: "http://ecykt.gdbtu.edu.cn/")!, isUserTap: true, sourceHost: ecykt), .cancel)
        XCTAssertEqual(RechargeNavigation.decide(URL(string: "https://evil.example/")!, isUserTap: true, sourceHost: ecykt), .cancel)
        XCTAssertEqual(RechargeNavigation.decide(URL(string: "alipays://platformapi/startapp")!, isUserTap: true, sourceHost: ecykt), .openExternal)
        XCTAssertEqual(RechargeNavigation.decide(URL(string: "weixin://wap/pay")!, isUserTap: true, sourceHost: ecykt), .openExternal)
        XCTAssertEqual(RechargeNavigation.decide(URL(string: "alipays://platformapi/startapp")!, isUserTap: false, sourceHost: ecykt), .cancel)
        XCTAssertEqual(RechargeNavigation.decide(URL(string: "alipays://platformapi/startapp")!, isUserTap: true, sourceHost: "portal.gdbtu.edu.cn"), .cancel)
    }
}

final class SchoolElectricityTests: XCTestCase {
    /// Campus-wide rows + one synthetic row for the faked user room.
    static func campusMeters(extra: [String], comAddresses: [String]? = nil) throws -> Fixture {
        let f = try FixtureLoader.load("ecykt/electric-getMeterStatus-ok")
        return T.editingData(f) { data in
            guard let text = data.text, case .array(var rows)? = try? JSONValue.parse(text) else { return }
            for (i, name) in extra.enumerated() {
                rows.append(.object(["comAddress": .string(comAddresses?[i] ?? "00000000099\(i + 1)"), "piplineName": .string(name),
                                     "type": .string("电表"), "leftMoney": .string("36.92"), "remaining": .string("52.00"),
                                     "onlineStatus": .string("在线")]))
            }
            data = .string(String(decoding: (try? JSONValue.array(rows).encoded()) ?? Data(), as: UTF8.self))
        }
    }

    static func serveTree(_ h: Harness) throws {
        for n in ["root", "level1", "level2", "level3", "level4"] {
            try h.server.serve("ecykt/electric-getBuildingInfo-" + n, matchBody: ["server", "buildingID"])
        }
        try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
        // Other apartments are empty in this synthetic tree.
        h.server.respond("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/api/electricnew/service",
                         bodyMatch: ["server": "/api/getBuildingInfo"], body: Data(#"{"code":0,"msg":"获取成功","data":"[]"}"#.utf8))
    }

    func testMatchesByPiplineNameAndSavesRoomNode() async throws {
        let h = Harness()
        try h.signedIn()
        h.server.serve(try Self.campusMeters(extra: ["99栋991"]), matchBody: ["server", "buildingID"])
        try Self.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .matched(let binding, let meter) = result else { return XCTFail("\(result)") }
        var expected = Harness.roomBinding
        expected.location = "星湖校区 · 半山公寓 · 99栋 · 991"
        XCTAssertEqual(binding, expected)
        XCTAssertEqual(meter.name, "99栋991")
        XCTAssertEqual(try h.vault.profile()?.meter, expected)
        XCTAssertTrue(h.server.unmatched.isEmpty)
        XCTAssertEqual(h.server.requests.filter { $0.bodyField("server") == "/api/getMeterStatus" && $0.bodyField("buildingID") == "991001" }.count, 0,
                       "no campus-wide meter read")
    }

    /// The lookup's reads are all small (one level, one room): none asks for more than the client's wait.
    func testEveryLookupReadKeepsTheClientsWait() async throws {
        let h = Harness()
        try h.signedIn()
        try Self.serveTree(h)
        _ = try await h.session().resolveElectricity()
        let electric = h.server.requests(path: "/electricnew/service")
        XCTAssertGreaterThan(electric.count, 5)
        XCTAssertTrue(electric.allSatisfy { $0.timeout == URLSessionHTTPClient.requestTimeout }, "\(electric.map(\.timeout))")
    }

    /// A meter bound to its room node is one row: the client's own wait.
    func testARefreshOfARoomBindingKeepsTheClientsWait() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
        try h.server.serve("ecykt/card-getRecordList-ok")
        _ = await h.refresher().refresh(inBackground: true)
        let room = h.server.requests(path: "/electricnew/service").filter { $0.bodyField("buildingID") == Harness.roomBinding.nodeID }
        XCTAssertEqual(room.count, 1)
        XCTAssertEqual(room[0].timeout, URLSessionHTTPClient.requestTimeout)
    }

    /// The dorm's building is in no apartment: nothing is bound (no campus-wide binding).
    func testNoRoomFoundBindsNothing() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/electric-getBuildingInfo-root", matchBody: ["server", "buildingID"])
        h.server.respond("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/api/electricnew/service",
                         bodyMatch: ["server": "/api/getBuildingInfo"], body: Data(#"{"code":0,"msg":"获取成功","data":"[]"}"#.utf8))
        let result = try await h.session().resolveElectricity()
        guard case .stopped(let stop) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(stop.level, .apartment)
        XCTAssertEqual(stop.path.map(\.id), ["991001"])
        XCTAssertNil(try h.vault.profile()?.meter)
    }

    func testZeroOrManyMatchingRoomsGoToThePickerOrTheList() async throws {
        let none = Harness()
        try none.signedIn()
        MeterWalkTests.level(none, MeterWalkTests.floor.id, [("989", "991001001000109000001001")])
        try Self.serveTree(none)
        let r0 = try await none.session().resolveElectricity()
        guard case .stopped(let stop) = r0 else { return XCTFail("\(r0)") }
        XCTAssertEqual(stop.level, .room)
        XCTAssertNil(try none.vault.profile()?.meter)

        let many = Harness()
        try many.signedIn()
        MeterWalkTests.level(many, MeterWalkTests.floor.id, [("991", MeterWalkTests.room.id), ("991房", "991001001000109000001009")])
        MeterWalkTests.meters(many, "991001001000109000001009", [("000000000999", "99栋 991")])
        try Self.serveTree(many)
        let r2 = try await many.session().resolveElectricity()
        guard case .chooseAmong(let list) = r2 else { return XCTFail("\(r2)") }
        XCTAssertEqual(list.map(\.room?.id), [MeterWalkTests.room.id, "991001001000109000001009"])
        XCTAssertNil(try many.vault.profile()?.meter)
    }

    /// Two 99栋 in different apartments, neither listing the dorm's room: the walk stops at the
    /// apartments with both offered; nothing is guessed.
    func testSameNamedBuildingsStopAtTheirApartments() async throws {
        let h = Harness()
        try h.signedIn(residence: "星湖校区99栋9号1层998房")
        MeterWalkTests.level(h, "991001002", [("99栋", "991001002000109")])
        try Self.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .stopped(let stop) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(stop.level, .apartment)
        XCTAssertEqual(stop.suggested, ["991001001", "991001002"])
        XCTAssertTrue(h.server.unmatched.isEmpty)
        XCTAssertNil(try h.vault.profile()?.meter, "nothing is saved until the user picks")
    }

    /// Two same-named rooms both report one meter: neither is guessed; both are offered, each
    /// bound to its own room when picked.
    func testOneMeterInTwoSameNamedRoomsIsOfferedForEach() async throws {
        let h = Harness()
        try h.signedIn()
        MeterWalkTests.level(h, MeterWalkTests.floor.id, [("991", MeterWalkTests.room.id), ("991", "991001001000109000001004")])
        MeterWalkTests.meters(h, "991001001000109000001004", [("000000000991", "99栋991")])
        try Self.serveTree(h)
        let session = h.session()
        let result = try await session.resolveElectricity()
        guard case .chooseAmong(let list) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(Set(list.map(\.id)).count, 2)
        XCTAssertNil(try h.vault.profile()?.meter)
        try await session.chooseMatchedMeter(list[1], since: await session.personStamp())
        XCTAssertEqual(try h.vault.profile()?.meter?.nodeID, "991001001000109000001004")
    }

    /// More same-named rooms than are read one by one: stopped at the rooms, all of them offered.
    func testMoreSameNamedRoomsThanAreReadStopAtTheRooms() async throws {
        let h = Harness()
        try h.signedIn()
        let rooms = (1...9).map { ("991", "99100100100010900000100\($0)") }
        MeterWalkTests.level(h, MeterWalkTests.floor.id, rooms)
        try Self.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .stopped(let stop) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(stop.level, .room)
        XCTAssertEqual(stop.suggested, rooms.map(\.1))
        XCTAssertTrue(h.server.requests.allSatisfy { $0.bodyField("server") != "/api/getMeterStatus" }, "no room read one by one")
    }

    /// The room lists two meters of its name: nothing tells them apart, so the picker at the rooms.
    func testTwoMetersOfTheRoomsNameGoToThePicker() async throws {
        let h = Harness()
        try h.signedIn()
        MeterWalkTests.meters(h, MeterWalkTests.room.id, [("000000000991", "99栋991"), ("000000000992", "99栋991")])
        try Self.serveTree(h)
        let result = try await h.session().resolveElectricity()
        guard case .stopped(let stop) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(stop.suggested, [MeterWalkTests.room.id])
        XCTAssertNil(try h.vault.profile()?.meter)
    }

    /// Candidates in two rooms with one comAddress still have their own ids.
    func testCandidateIdsIncludeTheRoom() {
        let meter = Meter(comAddress: "000000000991", name: "99栋991")
        let campus = PowerNode(id: "991001", name: "星湖校区")
        func path(_ apartment: String, _ room: String) -> [PowerNode] {
            [campus, PowerNode(id: apartment, name: "公寓"), PowerNode(id: apartment + "9", name: "99栋"),
             PowerNode(id: apartment + "91", name: "1楼"), PowerNode(id: room, name: "991")]
        }
        let a = MeterCandidate(meter: meter, path: path("991001001", "991001001000109000001003"))
        let b = MeterCandidate(meter: meter, path: path("991001002", "991001002000109000001003"))
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(MeterCandidate(meter: meter, path: [campus]).id, a.id)
    }

    func testNoParsedAddress() async throws {
        let h = Harness()
        try h.signedIn(residence: "暂无宿舍")
        let r = try await h.session().resolveElectricity()
        XCTAssertEqual(r, .noAddress)
        XCTAssertTrue(h.server.requests.isEmpty)
    }
}

final class SchoolSignInTests: XCTestCase {
    func testNativeSignInSavesSessionAndResidence() async throws {
        let h = Harness()
        try h.server.serve("portal/getMyInfo-ok")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "REDACTED_TOKEN_2"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let summary = try await h.session().signIn(portalToken: PortalToken("PORTAL"), owning: .unchecked)
        XCTAssertEqual(summary.cardholder, "测试员")
        XCTAssertEqual(summary.residence?.address?.meterName, "99栋991")
        XCTAssertEqual(try h.vault.portalToken(), stamped(PortalToken("PORTAL"), h))
        XCTAssertEqual(try h.vault.ecyktSession()?.cardUnionID, "TESTid00000000000000000000000001")
        XCTAssertEqual(try h.vault.profile()?.residence?.raw, "星湖校区99栋9号1层991房")
    }

    func testAdoptWebStateFallback() async throws {
        let h = Harness()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
        let summary = try await h.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertEqual(summary.cardholder, "测试员")
        let s = try XCTUnwrap(try h.vault.ecyktSession())
        XCTAssertEqual(s.token, "REDACTED_TOKEN_2")
        XCTAssertEqual(s.syscustid, T.syscustid)
        await T.expectError(.malformed(.ecykt, "elecampus_state")) { _ = try await h.session().adoptWebState(Data("{}".utf8), owning: .unchecked) }
    }

    func testSignInWithBadTicketExchangeSavesNothing() async throws {
        let h = Harness()
        try h.server.serve("portal/getMyInfo-ok")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: Data())
        await T.expectError(.badRequest(.ecykt)) { _ = try await h.session().signIn(portalToken: PortalToken("PORTAL"), owning: .unchecked) }
        XCTAssertNil(try h.vault.ecyktSession())
        XCTAssertNil(try h.vault.portalToken())
    }
}

extension Fixture {
    /// Same reply, served on another path of the same host.
    func withURLPath(_ path: String) -> Fixture {
        var f = self
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        c.path = path
        f.url = c.url!
        return f
    }
}

/// The card's recent records are read with the balance, in the same refresh.
final class CardActivityRefreshTests: XCTestCase {
    func testRecordsOfThreeSchoolDaysAreStoredWithTheBalance() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/card-getRecordList-ok")
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .ok)
        let activity = try XCTUnwrap(report.snapshot.activity.value)
        XCTAssertEqual(activity.records.count, 5)
        XCTAssertEqual(activity.records.first?.title, "蓝牙热水(中卡)(蓝牙热水(中卡))热水POS01(中卡)")
        XCTAssertFalse(activity.complete, "36 records, 5 came back")
        let request = try XCTUnwrap(h.server.requests(path: "/card/getRecordList").first)
        XCTAssertEqual(request.bodyField("begin"), "20261028", "the school's day: 02:53 on the 30th")
        XCTAssertEqual(request.bodyField("end"), "20261030")
        XCTAssertEqual(request.bodyField("pageSize"), String(CardActivity.pageSize))
        XCTAssertEqual(h.server.requests(path: "/card/getRecordList").count, 1)
        XCTAssertEqual(report.snapshot.activity.fetchedAt, h.clock.now)
        XCTAssertEqual(try h.snapshots.loadSnapshot()?.activity, report.snapshot.activity)
        XCTAssertTrue(h.server.unmatched.isEmpty)
    }

    /// The balance and the meter are stored before the card records answer.
    func testTheNumbersAreStoredBeforeTheRecordsAnswer() async throws {
        var h = Harness()
        let seen = Box<HomeSnapshot?>(nil)
        let snapshots = h.snapshots
        h.beforeRecords = {
            for _ in 0..<300 {
                if let stored = (try? snapshots.loadSnapshot()) ?? nil, stored.card.value != nil { seen.value = stored; return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        try h.signedIn(meter: Harness.roomBinding)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
        try h.server.serve("ecykt/card-getRecordList-ok")
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .ok)
        let early = try XCTUnwrap(seen.value, "balance stored while the records were still being read")
        XCTAssertNotNil(early.power.value)
        XCTAssertNil(early.activity.value)
        XCTAssertNotNil(report.snapshot.activity.value, "the records land after")
        XCTAssertEqual(try h.snapshots.loadSnapshot(), report.snapshot)
    }

    /// Records slower than their timeout are given up: the balance is stored all the same and
    /// the last records stay, marked as not updated.
    func testSlowRecordsAreGivenUpAndTheBalanceKept() async throws {
        var h = Harness()
        h.recordsTimeout = 0.3
        h.beforeRecords = { try? await Task.sleep(nanoseconds: 3_000_000_000) }
        try h.signedIn()
        var old = HomeSnapshot()
        let earlier = h.clock.now.addingTimeInterval(-3600)
        old.activity.succeed(CardActivity(records: [], begin: "20261028", end: "20261030", complete: true), at: earlier)
        old.checkedAt = earlier
        try h.snapshots.saveSnapshot(old)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/card-getRecordList-ok")
        let started = Date()
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5, "not waited for")
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertNotNil(report.snapshot.card.value)
        XCTAssertEqual(report.snapshot.activity.value, old.activity.value, "the last records stay")
        XCTAssertEqual(report.snapshot.activity.fetchedAt, earlier)
        XCTAssertEqual(report.snapshot.activity.error, .timedOut)
        XCTAssertEqual(try h.snapshots.loadSnapshot(), report.snapshot)
    }

    /// Records that can't be read leave the balance alone, and the last records stay with their time.
    func testUnreadableRecordsDoNotStopTheBalance() async throws {
        let h = Harness()
        try h.signedIn()
        let earlier = CardActivity(records: [], begin: "20261026", end: "20261028", complete: true)
        let before = h.clock.now.addingTimeInterval(-3600)
        try h.snapshots.saveSnapshot(HomeSnapshot(activity: Tile(value: earlier, fetchedAt: before), checkedAt: before))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 790))
        XCTAssertEqual(report.snapshot.activity.value, earlier)
        XCTAssertEqual(report.snapshot.activity.fetchedAt, before)
        XCTAssertNotNil(report.snapshot.activity.error)
    }
}

/// A value a stub server's gate can set and the test read afterwards.
final class Box<T>: @unchecked Sendable {
    // @unchecked: guarded by `lock`.
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Holds the card records request in an async wait before passing it on.
struct HeldRecordsClient: HTTPClient {
    let inner: HTTPClient
    let hold: @Sendable () async -> Void
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.path.hasSuffix("/getRecordList") { await hold() }
        return try await inner.send(request)
    }
}
