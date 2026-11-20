import XCTest
import Core
@testable import XiaoRiChang

/// The balance hot water goes by belongs to whoever is signed in now. A refresh hands its own
/// read to `ShowerModel`; 退出登录 and an account switch take it away in the same step that holds
/// hot water (before any wait), and take back a start that hasn't sent its authorize request; a
/// read that began for the previous person never comes back; the next person's own read decides.
/// Synthetic school and platform, fake stores: nothing real is read or sent.
@MainActor
final class ShowerBalanceAccountTests: XCTestCase {
    /// The school: the card check for `SYNTHETIC-CARD-A` and its balance (`yuan`), optionally
    /// held until `release`; anything else is offline.
    final class School: HTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var _yuan: Double
        private var _hold = false
        private var _asked = 0
        private var waiting: CheckedContinuation<Void, Never>?
        init(yuan: Double) { _yuan = yuan }
        var yuan: Double { get { lock.withLock { _yuan } } set { lock.withLock { _yuan = newValue } } }
        var hold: Bool { get { lock.withLock { _hold } } set { lock.withLock { _hold = newValue } } }
        var balanceAsked: Int { lock.withLock { _asked } }
        var isHolding: Bool { lock.withLock { waiting != nil } }
        func release() { lock.withLock { let w = waiting; waiting = nil; _hold = false; return w }?.resume() }

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let path = request.url.path
            if path.hasSuffix("/getSysBindCustInfo") {
                return Self.json(#"{"code":0,"msg":"获取成功","data":[{"custid":"SYNTHETIC-CUST","custunionid":"SYNTHETIC-CARD-A","custname":"测试员"}]}"#)
            }
            if path.hasSuffix("/getUserBalance") {
                let held = lock.withLock { _asked += 1; return _hold }
                if held { await withCheckedContinuation { c in lock.withLock { waiting = c } } }
                return Self.json(#"{"code":0,"msg":"获取成功","data":\#(yuan)}"#)
            }
            throw ServiceError.offline
        }
        static func json(_ body: String) -> HTTPResponse {
            HTTPResponse(status:200, headers:["Content-Type":"application/json"], body:Data(body.utf8))
        }
    }

    var school: School!
    var link: ScriptedControllerLink!
    var http: CountingShowerHTTP!
    var access: FakeBluetoothAccess!
    var store: ScriptedStore!

    override func setUp() async throws {
        school = School(yuan:-0.5)
        link = ScriptedControllerLink()
        http = CountingShowerHTTP()
        access = FakeBluetoothAccess()
        store = ScriptedStore()
    }

    static let positive = ShowerBalance(amount:Money(fen:1250), readAt:Date())
    static let owed = ShowerBalance(amount:Money(fen:-50), readAt:Date())

    /// Person A signed in (card session stored), hot water set up and matched.
    func models() async throws -> (CampusModel, ShowerModel) {
        try StoredSchoolVault(store:store).saveEcyktSession(EcyktSession(token:"SYNTHETIC-A", syscustid:"SYNTHETIC-SYS",
                                                                         cardUnionID:"SYNTHETIC-CARD-A"))
        var binding = Fixture.binding
        binding.matchedAt = Date(timeIntervalSince1970:1_800_000_000)
        binding.peripheralID = "P"
        try StoredShowerVault(store:store).saveBinding(binding)
        let lease = LeaseFile(url:FileManager.default.temporaryDirectory.appendingPathComponent("debt-lease-\(UUID().uuidString)"))
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:school, showerHTTP:http, laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:link, leaseFile:lease,
                                      applicationSupport:try Fixture.supportWithProfile(), sharedDidChange:{})
        let reminders = Reminders.sample(defaults:services.defaults)
        let shower = ShowerModel(services:services, reminders:reminders, activities:nil, gate:LiveShowerGate(),
                                 bluetoothAccess:access)
        let campus = CampusModel(services:services, stack:services.schoolStack(), reminders:reminders) { shower }
        await shower.reloadProfile()
        await waitUntil { shower.gateRecord != .notLoaded && shower.engine != nil }
        XCTAssertTrue(campus.configured, "A is signed in")
        XCTAssertTrue(shower.mayStart, "hot water is ready")
        return (campus, shower)
    }

    func shortcutRefusal(_ shower: ShowerModel) async -> String? {
        do { _ = try await shower.startFromShortcut(clear:false); return nil }
        catch let failure as ShowerActionFailure { return failure.message }
        catch { return "\(error)" }
    }

    // MARK: A refresh feeds the gate

    /// A refresh that read −0.50 for this login's card hands it to hot water: 开始洗澡 is refused.
    func testARefreshHandsItsOwnBalanceToHotWater() async throws {
        let (campus, shower) = try await models()
        await campus.refresh(force:true)
        XCTAssertEqual(campus.balance, Decimal(string:"-0.5"), "home shows it")
        XCTAssertEqual(shower.balance?.amount, Money(fen:-50))
        XCTAssertTrue(shower.balanceBlocks)
        XCTAssertEqual(shower.startBlock, .balanceNegative)
    }

    /// A positive read lets a start go, and replaces an earlier −0.50.
    func testAPositiveReadReplacesTheNegativeOne() async throws {
        let (campus, shower) = try await models()
        await campus.refresh(force:true)
        school.yuan = 12.5
        await campus.refresh(force:true)
        XCTAssertEqual(shower.balance?.amount, Money(fen:1250))
        XCTAssertFalse(shower.balanceBlocks)
        XCTAssertTrue(shower.mayStart)
    }

    // MARK: 退出登录

    /// 退出登录 takes the balance away in the same step (no wait): no −0.50 of A is left behind.
    func testSignOutClearsTheBalanceAtOnce() async throws {
        let (campus, shower) = try await models()
        shower.noteBalance(Self.owed)
        campus.signOut()
        XCTAssertNil(shower.balance, "cleared synchronously with the sign-out")
    }

    /// A start reading the controller when 退出登录 comes: its permit is revoked there and then.
    func testSignOutRevokesAStartThatHasNotAuthorized() async throws {
        link.holdExchange = true
        let (campus, shower) = try await models()
        shower.noteBalance(Self.positive)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        await waitUntil { self.link.isHolding }
        let permit = shower.startSlot?.permit
        campus.signOut()
        XCTAssertEqual(permit?.isOpen, false, "revoked in the same step")
        link.release(FakeFramesApp.idle)
        await campus.signOutsFinished()
        await pause(50)
        XCTAssertEqual(http.sent, 0, "no authorize request")
    }

    /// A refresh that began for A answers after 退出登录 (either sign): it never reaches hot water.
    func testALateReadAfterSignOutIsNotUsed() async throws {
        for yuan in [-0.5, 12.5] {
            try await setUp()
            school.yuan = yuan
            let (campus, shower) = try await models()
            school.hold = true
            let refresh = Task { await campus.refresh(force:true) }
            await waitUntil { self.school.isHolding }
            XCTAssertTrue(school.isHolding, "\(yuan): A's balance read is out")
            campus.signOut()
            school.release()
            await refresh.value
            await campus.signOutsFinished()
            XCTAssertNil(shower.balance, "\(yuan): A's late read is not hot water's balance")
        }
    }

    // MARK: Account switch (A → B)

    /// The switch holds hot water, revokes a start that hasn't authorized and clears the balance
    /// before its first wait: in the gap while the widget snapshot is cleared, no start (the page
    /// or Siri) gets anywhere, and A's balance is gone.
    func testASwitchBlocksAndClearsBeforeItsFirstWait() async throws {
        link.holdExchange = true
        let (campus, shower) = try await models()
        shower.noteBalance(Self.positive)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        await waitUntil { self.link.isHolding }
        let permit = shower.startSlot?.permit
        var inGap: (balance: ShowerBalance?, permitOpen: Bool?, mayStart: Bool, tap: ShowerStartTap?, siri: String?)?
        campus.afterSnapshotCleared = {
            let tap = shower.tapStart(.home)
            let siri = await self.shortcutRefusal(shower)
            inGap = (shower.balance, permit?.isOpen, shower.mayStart, tap, siri)
        }
        await campus.previousPersonCleared(unconfirmed:false, dormAndMeterCleared:false, since:campus.signOutGeneration)
        link.release(FakeFramesApp.idle)
        await pause(100)

        let gap = try XCTUnwrap(inGap, "the hook ran")
        XCTAssertNil(gap.balance, "A's balance is gone before the first wait")
        XCTAssertEqual(gap.permitOpen, false, "A's start was revoked before the first wait")
        XCTAssertFalse(gap.mayStart)
        XCTAssertNotEqual(gap.tap, .started(firstCheck:false), "no start in the gap")
        XCTAssertNotEqual(gap.tap, .started(firstCheck:true), "no start in the gap")
        XCTAssertNotNil(gap.siri, "Siri is refused in the gap")
        XCTAssertEqual(http.sent, 0, "no authorize request")
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand], "only A's read-only probe; no open command")
    }

    /// A refresh that began for A answers after the switch (either sign): never hot water's.
    func testALateReadAfterASwitchIsNotUsed() async throws {
        for yuan in [-0.5, 12.5] {
            try await setUp()
            school.yuan = yuan
            let (campus, shower) = try await models()
            school.hold = true
            let refresh = Task { await campus.refresh(force:true) }
            await waitUntil { self.school.isHolding }
            await campus.previousPersonCleared(unconfirmed:false, dormAndMeterCleared:false, since:campus.signOutGeneration)
            school.release()
            await refresh.value
            XCTAssertNil(shower.balance, "\(yuan): A's late read is not hot water's balance")
        }
    }

    /// After the switch, B's own read decides: −0.50 read for B refuses B's start.
    func testTheNextPersonsOwnReadDecides() async throws {
        school.yuan = 12.5
        let (campus, shower) = try await models()
        await campus.refresh(force:true)
        await campus.previousPersonCleared(unconfirmed:false, dormAndMeterCleared:false, since:campus.signOutGeneration)
        XCTAssertNil(shower.balance, "nothing of A's")
        school.yuan = -0.5
        await campus.refresh(force:true)
        XCTAssertEqual(shower.balance?.amount, Money(fen:-50), "B's own read")
        XCTAssertTrue(shower.balanceBlocks)
    }
}
