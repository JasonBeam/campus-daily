//
//  AccountSwitchSnapshotTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

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

    /// The school answering for one card at a time (`card`; its balance `yuan`; anything else
    /// offline). Requests made while `holding` (a refresh's) wait until `open()`, then are
    /// answered for whoever `card` is then.
    private final class HeldSchool: HTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var holding = true
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var answer: String
        private let yuan: Double
        init(card: String, yuan: Double) { answer = card; self.yuan = yuan }
        var card: String {
            get { lock.withLock { answer } }
            set { lock.withLock { answer = newValue } }
        }
        var held: Int { lock.withLock { waiters.count } }
        func stopHolding() { lock.withLock { holding = false } }
        func open() {
            let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                holding = false
                defer { waiters = [] }
                return waiters
            }
            waiting.forEach { $0.resume() }
        }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            await withCheckedContinuation { (go: CheckedContinuation<Void, Never>) in
                let wait = lock.withLock { () -> Bool in
                    guard holding else { return false }
                    waiters.append(go)
                    return true
                }
                if !wait { go.resume() }
            }
            let path = request.url.path
            let body: String
            if path.hasSuffix("/getSysBindCustInfo") {
                body = #"{"code":0,"msg":"获取成功","data":[{"custid":"SYNTHETIC-CUST","custunionid":"\#(card)","custname":"测试员"}]}"#
            } else if path.hasSuffix("/getUserBalance") {
                body = #"{"code":0,"msg":"获取成功","data":\#(yuan)}"#
            } else {
                throw ServiceError.offline
            }
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

    private func makeCampus(_ services: CampusServices, reminders: Reminders? = nil) -> CampusModel {
        let reminders = reminders ?? Reminders.sample(defaults:services.defaults)
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

    /// B signs in over A without a sign-out: the records pages are made again for B (none of A's
    /// span, term start or records stays in memory) and A's stored choices are gone.
    func testASwitchGivesTheRecordsPagesANewIdentityAndForgetsTheStats() async throws {
        let store = ScriptedStore()
        try seedPersonA(store)
        let services = makeServices(store, http:CardCheck(card:"SYNTHETIC-CARD-B"), lease:nil)
        let campus = makeCampus(services)
        services.defaults.set("term", forKey:SpendSpan.storeKey)
        services.defaults.set("20261114", forKey:TermStartStore.key)
        SpendCategoryStore(preferences:services.defaults).set(Set(SpendCategories.all))
        let before = campus.recordsIdentity
        let kept = campus.recordsMemory
        var history = CardHistory(now:Date())
        if let query = history.nextQuery { history.receive(CardRecordPage(total:0, rows:[]), for:query) }
        kept.keep(history, stamp:0)

        try await campus.adoptWebState(Self.webLogin(card:"SYNTHETIC-CARD-B"))

        XCTAssertNotEqual(campus.recordsIdentity, before)
        XCTAssertNil(services.defaults.object(forKey:SpendSpan.storeKey))
        XCTAssertNil(services.defaults.object(forKey:TermStartStore.key))
        XCTAssertNil(services.defaults.object(forKey:SpendCategoryStore.key))
        XCTAssertTrue(kept.isEmpty, "A's records are not kept for B")
        XCTAssertTrue(campus.recordsMemory.isEmpty)
    }

    /// B signs in over A and 校园卡记录 opens before A's numbers are cleared from home: home's
    /// last records are still A's then, so no page shows them, B's new one or A's still open.
    func testASwitchedPersonsPageIsNotPrefilledWithThePreviousPersonsRecords() async throws {
        let store = ScriptedStore()
        try StoredSchoolVault(store:store).saveEcyktSession(EcyktSession(token:"SYNTHETIC-A", syscustid:"SYNTHETIC-SYS",
                                                                        cardUnionID:"SYNTHETIC-CARD-A"))
        try SharedSnapshotStore(store:store).saveSnapshot(SampleData.homeSnapshot(now:Date()))
        let campus = makeCampus(makeServices(store, http:CardCheck(card:"SYNTHETIC-CARD-B"), lease:nil))
        let pageA = CardRecordsSource.school(campus)
        XCTAssertNotNil(pageA.prefill?(), "A's own page shows home's records")

        let held = ShowerBalanceAccountTests.Gate()
        var cleaning = false
        campus.afterSnapshotCleared = { cleaning = true; await held.wait() }
        let signIn = Task { try await campus.adoptWebState(Self.webLogin(card:"SYNTHETIC-CARD-B")) }
        await waitUntil { cleaning }
        XCTAssertNotNil(campus.snapshot.activity.value, "home still holds A's records while the clean-up runs")
        let pageB = CardRecordsSource.school(campus)
        XCTAssertNil(pageB.prefill?(), "B's page, opened at once")
        XCTAssertNil(pageA.prefill?(), "A's page, still open")

        held.open()
        try await signIn.value
        XCTAssertNil(pageB.prefill?())
    }

    /// A home refresh started for A reads A's numbers (¥56.50) after B signed in, before A's
    /// widget snapshot is cleared (no lease file: nothing keeps its write out of that gap):
    /// home never shows them, reminders never judge them, and the clean-up leaves none stored.
    func testARefreshStartedBeforeASwitchDoesNotPutThePreviousPersonBack() async throws {
        let store = ScriptedStore()
        try seedPersonA(store)
        let fresh = Money(fen:5650)
        func isA(_ snapshot: HomeSnapshot?) -> Bool { showsPersonA(snapshot) || snapshot?.card.value == fresh }
        let http = HeldSchool(card:"SYNTHETIC-CARD-A", yuan:56.5)
        let services = makeServices(store, http:http, lease:nil)
        let reminders = Reminders.sample(defaults:services.defaults)
        var judged: [HomeSnapshot] = []
        reminders.campusEvaluated = { judged.append($0) }
        let campus = makeCampus(services, reminders:reminders)
        XCTAssertTrue(showsPersonA(campus.snapshot))

        let refreshed = Counter()
        let refresh = Task { await campus.refresh(force:true); refreshed.bump() }
        await waitUntil { http.held > 0 }
        XCTAssertGreaterThan(http.held, 0, "A's refresh is reading")
        http.stopHolding()
        http.card = "SYNTHETIC-CARD-B"

        // B is signed in (stored, A's snapshot marked stale); right before A's snapshot is
        // cleared, A's read gets its answers and finishes.
        var storedInTheGap: HomeSnapshot?
        var homeInTheGap: HomeSnapshot?
        campus.beforeSnapshotCleared = {
            http.card = "SYNTHETIC-CARD-A"
            http.open()
            await waitUntil { refreshed.value > 0 }
            storedInTheGap = try? SharedSnapshotStore(store:store).loadSnapshot()
            homeInTheGap = campus.snapshot
        }
        try await campus.adoptWebState(Self.webLogin(card:"SYNTHETIC-CARD-B"))
        await refresh.value

        XCTAssertEqual(refreshed.value, 1, "A's refresh finished before the clean-up's clear")
        XCTAssertEqual(storedInTheGap?.card.value, fresh, "A's read was written in the gap")
        // Home still holds A's earlier numbers until the clean-up empties it; not the new read.
        XCTAssertNotEqual(homeInTheGap?.card.value, fresh, "home, A's refresh just back")
        XCTAssertFalse(isA(campus.snapshot), "home, after the clean-up")
        XCTAssertFalse(isA(try SharedSnapshotStore(store:store).loadSnapshot()), "stored, after the clean-up")
        XCTAssertEqual(try SharedSnapshotStore(store:store).loadSnapshot(), .empty)
        XCTAssertNil(try store.read(.sharedSnapshotStale))
        XCTAssertFalse(judged.contains(where:isA), "reminders never judged A's numbers")
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
