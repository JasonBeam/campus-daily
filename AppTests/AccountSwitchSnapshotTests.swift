import XCTest
import Core
@testable import XiaoRiChang

/// Someone else signs in and the previous person's numbers can't be cleared (the Keychain refuses
/// the snapshot write): the app, a relaunch and the widget never show them again, the widget is
/// asked to draw again, and once the Keychain writes again the pending clear finishes offline.
@MainActor
final class AccountSwitchSnapshotTests: XCTestCase {
    /// The school's card check answers with `card`; anything else is offline.
    private final class CardCheck: HTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var answer: String
        init(card: String) { answer = card }
        var card: String {
            get { lock.withLock { answer } }
            set { lock.withLock { answer = newValue } }
        }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            guard request.url.path.hasSuffix("/getSysBindCustInfo") else { throw ServiceError.offline }
            let body = #"{"code":0,"msg":"获取成功","data":[{"custid":"SYNTHETIC-CUST","custunionid":"\#(card)","custname":"测试员"}]}"#
            return HTTPResponse(status:200, headers:["Content-Type":"application/json"], body:Data(body.utf8))
        }
    }

    private static func webLogin(card: String) -> CampusWebLogin {
        CampusWebLogin(state:Data(#"""
            {"logintoken":"SYNTHETIC-TOKEN","schoolid":"450010","loginInfo":{"syscustid":"SYNTHETIC-SYS","token":"SYNTHETIC-TOKEN"},"custInfo":{"custid":"SYNTHETIC-CUST","custunionid":"\#(card)"}}
            """#.utf8), dormAddress:"")
    }

    private static let previousBalance = Money(fen:4321)

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }

    private func leaseFile() -> LeaseFile {
        LeaseFile(url:FileManager.default.temporaryDirectory.appendingPathComponent("switch-lease-\(UUID().uuidString)"))
    }

    private func makeServices(_ store: ScriptedStore, http: HTTPClient, lease: LeaseFile?, redraws: Counter = Counter(),
                          support: URL? = nil) -> CampusServices {
        CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                       schoolHTTP:http, showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                       feedbackHTTP:nil, showerTransport:SampleShowerTransport(), leaseFile:lease,
                       applicationSupport:support, sharedDidChange:{ redraws.bump() })
    }

    private func makeCampus(_ services: CampusServices) -> CampusModel {
        let reminders = Reminders.sample(defaults:services.defaults)
        let shower = ShowerModel(services:services, reminders:reminders, activities:nil, gate:LiveShowerGate())
        return CampusModel(services:services, stack:services.schoolStack(), reminders:reminders) { shower }
    }

    /// Person A, signed in on the web page, with their balance in the shared snapshot.
    private func seedPersonA(_ store: ScriptedStore) throws {
        let vault = StoredSchoolVault(store:store)
        try vault.saveEcyktSession(EcyktSession(token:"SYNTHETIC-A", syscustid:"SYNTHETIC-SYS", cardUnionID:"SYNTHETIC-CARD-A"))
        var numbers = HomeSnapshot(checkedAt:Date(timeIntervalSinceNow:-3600))
        numbers.card.succeed(Self.previousBalance, at:Date(timeIntervalSinceNow:-3600))
        try SharedSnapshotStore(store:store).saveSnapshot(numbers)
    }

    private func showsPersonA(_ snapshot: HomeSnapshot?) -> Bool { snapshot?.card.value == Self.previousBalance }

    func testAFailedSnapshotClearOnASwitchNeverShowsThePreviousPerson() async throws {
        let store = ScriptedStore()
        try seedPersonA(store)
        let http = CardCheck(card:"SYNTHETIC-CARD-B")
        let lease = leaseFile()
        let services = makeServices(store, http:http, lease:lease)
        let campus = makeCampus(services)
        XCTAssertTrue(showsPersonA(campus.snapshot), "A's numbers before the switch")
        store.refusing = [.sharedSnapshot]

        // 1. B signs in: the clean-up can't write the snapshot.
        try await campus.adoptWebState(Self.webLogin(card:"SYNTHETIC-CARD-B"))
        XCTAssertFalse(showsPersonA(campus.snapshot), "after the switch")
        XCTAssertNotNil(campus.switchNotice)

        // 2. B signs in again (the same person now: nothing is cleaned up) and the refresh fails.
        try await campus.adoptWebState(Self.webLogin(card:"SYNTHETIC-CARD-B"))
        await campus.refresh(force:true)
        XCTAssertFalse(showsPersonA(campus.snapshot), "after a failed refresh of B")

        // 3. A relaunch on the same Keychain, and the widget's read.
        let relaunched = makeCampus(makeServices(store, http:http, lease:lease))
        XCTAssertFalse(showsPersonA(relaunched.snapshot), "after a relaunch")
        let widget = WidgetStoredData.read(snapshots:SharedSnapshotStore(store:store), vault:StoredSchoolVault(store:store))
        XCTAssertNotNil(widget)
        XCTAssertNil(widget?.snapshot, "the widget reads no snapshot")

        // 4. The Keychain writes again: the pending clear finishes without the network.
        store.refusing = []
        await relaunched.finishPendingClear()
        XCTAssertNil(try store.read(.sharedSnapshotStale))
        XCTAssertEqual(try SharedSnapshotStore(store:store).loadSnapshot(), .empty)
        XCTAssertFalse(showsPersonA(relaunched.snapshot))
    }

    func testASwitchAsksTheWidgetToRedrawEvenWhenTheClearFails() async throws {
        let store = ScriptedStore()
        try seedPersonA(store)
        let redraws = Counter()
        let campus = makeCampus(makeServices(store, http:CardCheck(card:"SYNTHETIC-CARD-B"), lease:nil, redraws:redraws))
        store.refusing = [.sharedSnapshot]
        try await campus.adoptWebState(Self.webLogin(card:"SYNTHETIC-CARD-B"))
        XCTAssertGreaterThanOrEqual(redraws.value, 1, "asked to draw again though nothing was written")
    }

    /// 退出登录 whose mark can't be written deletes nothing: it is a failed sign-out (still signed
    /// in, hot water held until the dorm is checked again), never a finished one.
    func testASignOutThatCannotMarkTakesTheFailedSignOutPath() async throws {
        let store = ScriptedStore()
        let showerVault = StoredShowerVault(store:store)
        try showerVault.saveBinding(Fixture.binding)
        let vault = StoredSchoolVault(store:store)
        try vault.saveAccount(SchoolAccount(account:"99100991"))
        try vault.saveEcyktSession(EcyktSession(token:"SYNTHETIC-A", syscustid:"SYNTHETIC-SYS", cardUnionID:"SYNTHETIC-CARD-A"))
        try vault.savePortalToken(PortalToken("SYNTHETIC-PORTAL"))
        let credentials = try vault.credentialBytes()
        let services = makeServices(store, http:SampleHTTPClient(), lease:nil, support:try Fixture.supportWithProfile())
        let reminders = Reminders.sample(defaults:services.defaults)
        let shower = ShowerModel(services:services, reminders:reminders, activities:nil, gate:LiveShowerGate())
        let campus = CampusModel(services:services, stack:services.schoolStack(), reminders:reminders) { shower }
        await waitUntil { shower.gateRecord != .notLoaded && shower.profileLoaded }
        XCTAssertTrue(shower.mayStart)
        store.refusing = [.sharedSnapshotStale, .sharedSnapshot]

        campus.signOut()
        await waitUntil { campus.signOutFailed }
        await campus.signOutsFinished()

        XCTAssertTrue(campus.signOutFailed)
        XCTAssertEqual(try vault.credentialBytes(), credentials, "nothing was deleted")
        XCTAssertEqual(try vault.account()?.account, "99100991")
        XCTAssertEqual(try showerVault.binding(), Fixture.binding, "the binding stays")
        XCTAssertEqual(shower.binding, Fixture.binding)
        XCTAssertTrue(shower.residenceReviewRequired)
        XCTAssertFalse(shower.mayStart)
    }
}
