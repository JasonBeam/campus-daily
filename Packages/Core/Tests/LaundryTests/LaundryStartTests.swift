import XCTest
import Foundation
@testable import Core

/// Whether the app is in front, switchable from a test (and from `beforeSend`).
final class FrontSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool
    init(_ value: Bool) { _value = value }
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }
}

/// 立刻洗衣: after payment, with the app in front, one pre-start read
/// and at most one `control/start` per order, ever. Normal orders send exactly what they did.
final class LaundryStartTests: XCTestCase {
    var store: InMemorySecureStore!
    var vault: StoredLaundryVault!
    var api: FakeLaundryAPI!
    var launcher: FakeLauncher!
    var sleeps: Sleeps!
    var front: FrontSwitch!
    var clock: TestClock!

    static let account = "acct-1"

    override func setUp() { reset() }

    func reset() {
        store = InMemorySecureStore()
        vault = StoredLaundryVault(store: store)
        api = FakeLaundryAPI()
        launcher = FakeLauncher()
        sleeps = Sleeps()
        front = FrontSwitch(true)
        clock = TestClock(L.t0.addingTimeInterval(10))
    }

    func engine(vault v: LaundryVault? = nil, account: String? = LaundryStartTests.account) throws -> LaundryEngine {
        let sleeps = self.sleeps!, front = self.front!, clock = self.clock!
        return try LaundryEngine(api: api, vault: v ?? vault, launcher: launcher, accountID: account,
                                 inFront: { front.value }, now: { clock.now }, sleep: { sleeps.record($0) })
    }

    var f2f: PaymentArguments {
        PaymentArguments(.object(["url": .string("alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url="
            + "https%3A%2F%2Fopenauth.alipay.com%2Foauth2%2FpublicAppAuthorize.htm%3Fredirect_uri%3Dhttps%253A%252F%252Fwx.zhinengxiyifang.cn%252Fstatic%252FcommonWasher%252Findex.html")]))
    }

    /// Order created (unpaid) and payment handed to Alipay; `returnedFromPayment` comes next.
    func paying(immediate: Bool, vault v: LaundryVault? = nil) async throws -> LaundryEngine {
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        api.methods = [.ok([PayChannel(channel: "alipayF2F", branchType: 0)])]
        api.arguments = [.ok(f2f)]
        let e = try engine(vault: v)
        let created = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard, immediate: immediate)
        XCTAssertEqual(created.immediate, immediate)
        let s = try await e.pay()
        XCTAssertEqual(s.phase, .paying)
        return e
    }

    /// A stored, paid (20) 立刻洗衣 order confirmed at `t0 + 10` by `acct-1`, not tried yet.
    func storePaid(immediate: Bool = true, start: LaundryStart? = nil) throws {
        var s = LaundryReducer.reduce(.empty, .confirm(L.draft, at: L.t0.addingTimeInterval(10), account: Self.account, immediate: immediate)).0
        s = LaundryReducer.reduce(s, .created(orderID: L.orderID)).0
        s = LaundryReducer.reduce(s, .orderRead(L.order("10"), at: L.t0.addingTimeInterval(11))).0
        s = LaundryReducer.reduce(s, .paymentMethods([PayChannel(channel: "alipay")], at: L.t0.addingTimeInterval(12))).0
        s = LaundryReducer.reduce(s, .returnedFromPayment).0
        s = LaundryReducer.reduce(s, .orderRead(L.order("20"), at: L.t0.addingTimeInterval(20))).0
        XCTAssertEqual(s.phase, .active)
        s.start = start
        try vault.saveCheckout(s.persistable)
    }

    func storedStart() throws -> LaundryStart? { try vault.checkout()?.start }

    // MARK: normal orders

    /// 正常洗衣: from payment to washing, the very requests the app sends today.
    func testNormalOrderSendsTodaysRequestsOnly() async throws {
        let e = try await paying(immediate: false)
        api.orders = [.ok(L.order("20"))]
        var s = try await e.returnedFromPayment()
        XCTAssertEqual(s.phase, .active)
        api.orders = [.ok(L.order("40", remain: 1800))]
        s = try await e.refresh()
        XCTAssertEqual(api.calls, ["create", "order", "methods", "arguments", "order", "order"])
        XCTAssertEqual(api.count("startCheck"), 0)
        XCTAssertEqual(api.count("start"), 0)
        XCTAssertNil(s.start)
        XCTAssertFalse(try XCTUnwrap(try vault.checkout()).immediate)
    }

    func testConfirmDefaultsToNormal() async throws {
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        let s = try await engine().confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        XCTAssertFalse(s.immediate)
    }

    // MARK: the happy path

    func testImmediateStartsOnceThenReadsUntilWashing() async throws {
        let e = try await paying(immediate: true)
        api.orders = [.ok(L.order("20")), .ok(L.order("40", remain: 1800))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        var s = try await e.returnedFromPayment()
        XCTAssertEqual(Array(api.calls.suffix(4)), ["order", "startCheck", "start", "order"])
        XCTAssertEqual(s.start, .started)
        XCTAssertTrue(s.order?.status.isWashing == true)
        XCTAssertEqual(sleeps.delays, [2, 2], "the payment poll's first step, then the post-start poll's")

        api.orders = [.ok(L.order("40", remain: 1700)), .ok(L.order("40", remain: 1600))]
        s = try await e.refresh()
        s = try await e.refresh()
        XCTAssertEqual(api.count("start"), 1)
        XCTAssertEqual(api.count("startCheck"), 1)
        XCTAssertEqual(s.start, .started)
    }

    func testStartRecordIsSavedBeforeTheRequestLeaves() async throws {
        let e = try await paying(immediate: true)
        let v = vault!
        api.beforeSend = { name in
            guard name == "start" else { return }
            guard case .sent? = try? v.checkout()?.start else { return XCTFail("start not recorded before sending") }
        }
        api.orders = [.ok(L.order("20")), .ok(L.order("40", remain: 1800))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        _ = try await e.returnedFromPayment()
        XCTAssertEqual(api.count("start"), 1)
    }

    func testStorageFailureBeforeStartSendsNothing() async throws {
        let flaky = FlakyLaundryVault(inner: vault) { c in
            if case .sent? = c?.start { return true }
            return false
        }
        let e = try await paying(immediate: true, vault: flaky)
        api.orders = [.ok(L.order("20"))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        do { _ = try await e.returnedFromPayment(); XCTFail("expected the storage stop") }
        catch { XCTAssertEqual(error as? LaundryEngineError, .storage) }
        XCTAssertEqual(api.count("start"), 0)
        XCTAssertNil(try storedStart())
        do { _ = try await e.refresh(); XCTFail() } catch { XCTAssertEqual(error as? LaundryEngineError, .storage) }
        XCTAssertEqual(api.count("start"), 0)
    }

    // MARK: unclear outcomes never resend

    func testUnclearOrRefusedStartIsNeverSentAgain() async throws {
        let cases: [(FakeLaundryAPI.Outcome<Bool>, LaundryStart)] = [
            (.fail(.timedOut), .pending(at: L.t0.addingTimeInterval(10))),
            (.fail(.offline), .pending(at: L.t0.addingTimeInterval(10))),
            (.fail(.malformed(.ujing, "data")), .pending(at: L.t0.addingTimeInterval(10))),
            (.fail(.uncertain(.ujing)), .pending(at: L.t0.addingTimeInterval(10))),
            (.fail(.rejected(.ujing, code: "errorMessage", message: "设备未关门")),
             .refused(message: "设备未关门", at: L.t0.addingTimeInterval(10))),
        ]
        for (outcome, expected) in cases {
            reset()
            try storePaid()
            api.startChecks = [.ok(L.check())]
            api.starts = [outcome]
            api.orders = Array(repeating: .ok(L.order("20")), count: 6)
            let s = try await engine().refresh()
            XCTAssertEqual(s.start, expected, "\(outcome)")
            XCTAssertEqual(api.count("start"), 1)
            XCTAssertEqual(api.count("order"), 6, "only reads after the start")
            XCTAssertEqual(try storedStart(), expected)

            // Relaunch, refresh twice: reads only.
            api.orders = [.ok(L.order("20")), .ok(L.order("20"))]
            let again = try engine()
            _ = try await again.refresh()
            let last = try await again.refresh()
            XCTAssertEqual(api.count("start"), 1, "\(outcome)")
            XCTAssertEqual(api.count("startCheck"), 1, "\(outcome)")
            XCTAssertEqual(last.start, expected)
        }
    }

    func testAcceptedButStillWaitingIsNotSentAgain() async throws {
        try storePaid()
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        api.orders = Array(repeating: .ok(L.order("20")), count: 8)
        let e = try engine()
        var s = try await e.refresh()
        XCTAssertEqual(s.start, .accepted(at: L.t0.addingTimeInterval(10)))
        s = try await e.refresh()
        s = try await e.refresh()
        XCTAssertEqual(api.count("start"), 1)
        XCTAssertEqual(s.start, .accepted(at: L.t0.addingTimeInterval(10)))
    }

    func testFiftyTwoAfterTheStartIsTheExistingAttention() async throws {
        try storePaid()
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        api.orders = [.ok(L.order("52"))]
        let s = try await engine().refresh()
        XCTAssertEqual(s.phase, .attention)
        XCTAssertEqual(api.count("start"), 1)
    }

    // MARK: the pre-start read

    func testPreStartReadThatIsNotThisPaidOrderNeverStarts() async throws {
        let checks: [(String, LaundryStartCheck)] = [
            ("other order", L.check(id: "OTHERORDER0002")),
            ("other machine", L.check(device: "test-device-0002")),
            ("other program", L.check(program: 2)),
            ("unpaid 20", L.check(paid: false)),
            ("17", L.check("17")),
            ("21", L.check("21")),
            ("40", L.check("40", remain: 1800)),
            ("50", L.check("50")),
            ("52", L.check("52")),
        ]
        for (name, check) in checks {
            reset()
            try storePaid()
            api.startChecks = [.ok(check)]
            api.starts = [.ok(true)]
            _ = try await engine().refresh()
            XCTAssertEqual(api.count("start"), 0, name)
            if case .blocked? = try storedStart() { XCTFail("\(name): not a reason to give up for good") }
        }
    }

    /// The price is compared in fen. Above the confirmed one, missing or zero: never started,
    /// and never looked at again (stored, kept over a relaunch).
    func testAPriceThatDoesNotMatchIsBlockedForGood() async throws {
        for (name, check) in [("above", L.check(price: 401)), ("missing", L.check(price: nil)), ("zero", L.check(price: 0))] {
            reset()
            try storePaid()
            api.startChecks = [.ok(check)]
            api.starts = [.ok(true)]
            let s = try await engine().refresh()
            XCTAssertEqual(s.start, .blocked(.price), name)
            XCTAssertEqual(try storedStart(), .blocked(.price), name)
            XCTAssertEqual(LaundryDisplay(s).startLine?.text, "这单的价格对不上，没帮你启动。", name)
            XCTAssertEqual(LaundryDisplay(s).startLine?.detail, "去 U净 App 里启动。", name)

            api.orders = [.ok(L.order("20")), .ok(L.order("20"))]
            let again = try engine()
            _ = try await again.refresh()
            let last = try await again.refresh()
            XCTAssertEqual(api.count("startCheck"), 1, "\(name): never looked at again")
            XCTAssertEqual(api.count("start"), 0, name)
            XCTAssertEqual(last.start, .blocked(.price), name)
        }
    }

    /// A read that fails to decode is a failed read: nothing changes, read again later.
    func testUnreadablePriceNeverStarts() async throws {
        try storePaid()
        api.startChecks = [.fail(.malformed(.ujing, "data.payPrice"))]
        let e = try engine()
        let s = try await e.refresh()
        XCTAssertEqual(api.count("start"), 0)
        XCTAssertNil(s.start)
        XCTAssertEqual(s.notice, .readFailed(.malformed(.ujing, "data.payPrice")))
    }

    func testMachinesThatNeedUjingAreBlockedForGood() async throws {
        let checks: [(LaundryStartCheck, LaundryStartBlock)] = [
            (L.check(module: 1), .unsupported),
            (L.check(module: nil), .unsupported),
            (L.check(online: false), .offline),
            (L.check(selfClean: true), .selfClean),
            (L.check(dispenser: true), .dispenser),
        ]
        for (check, reason) in checks {
            reset()
            try storePaid()
            api.startChecks = [.ok(check)]
            api.starts = [.ok(true)]
            let e = try engine()
            let s = try await e.refresh()
            XCTAssertEqual(s.start, .blocked(reason))
            XCTAssertEqual(try storedStart(), .blocked(reason))
            api.orders = [.ok(L.order("20"))]
            _ = try await e.refresh()
            XCTAssertEqual(api.count("startCheck"), 1, "never looked at again")
            XCTAssertEqual(api.count("start"), 0)
        }
    }

    func testPastTenMinutesIsBlocked() async throws {
        try storePaid()
        clock.now = L.t0.addingTimeInterval(10 + 601)
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        let e = try engine()
        let s = try await e.refresh()
        XCTAssertEqual(s.start, .blocked(.expired))
        XCTAssertEqual(api.count("start"), 0)

        // Seen paid by the payment poll after the window: blocked without the pre-start read.
        reset()
        clock.now = L.t0.addingTimeInterval(10)
        let p = try await paying(immediate: true)
        clock.now = L.t0.addingTimeInterval(10 + 601)
        api.orders = [.ok(L.order("20"))]
        let late = try await p.returnedFromPayment()
        XCTAssertEqual(late.start, .blocked(.expired))
        XCTAssertEqual(api.count("startCheck"), 0)
        XCTAssertEqual(api.count("start"), 0)
    }

    func testFailedPreStartReadChangesNothingAndIsReadAgainLater() async throws {
        try storePaid()
        api.startChecks = [.fail(.offline)]
        let e = try engine()
        var s = try await e.refresh()
        XCTAssertNil(s.start)
        XCTAssertEqual(api.count("start"), 0)
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        api.orders = [.ok(L.order("40", remain: 1800))]
        s = try await e.refresh()
        XCTAssertEqual(api.count("startCheck"), 2)
        XCTAssertEqual(api.count("start"), 1)
        XCTAssertEqual(s.start, .started)
    }

    // MARK: in front only

    func testInTheBackgroundNothingIsSentUntilTheAppIsInFront() async throws {
        let e = try await paying(immediate: true)
        front.value = false
        api.orders = [.ok(L.order("20"))]
        var s = try await e.returnedFromPayment()
        XCTAssertEqual(s.phase, .active)
        XCTAssertNil(s.start)
        XCTAssertEqual(api.count("startCheck"), 0)
        XCTAssertEqual(api.count("start"), 0)

        front.value = true
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        api.orders = [.ok(L.order("40", remain: 1800))]
        s = try await e.refresh()
        XCTAssertEqual(api.count("startCheck"), 1)
        XCTAssertEqual(api.count("start"), 1)
        XCTAssertEqual(s.start, .started)
    }

    /// Gone to the background after the pre-start read, before the start left: not tried.
    func testBackgroundBeforeTheStartLeavesMeansNotTried() async throws {
        try storePaid()
        let front = self.front!
        api.beforeSend = { name in if name == "startCheck" { front.value = false } }
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        let e = try engine()
        var s = try await e.refresh()
        XCTAssertNil(s.start)
        XCTAssertNil(try storedStart())
        XCTAssertEqual(api.count("start"), 0)

        api.beforeSend = nil
        front.value = true
        api.startChecks = [.ok(L.check())]
        api.orders = [.ok(L.order("40", remain: 1800))]
        s = try await e.refresh()
        XCTAssertEqual(api.count("start"), 1)
    }

    /// Once the request is handed to the network it is never taken back, whatever
    /// happens to the app or the reply.
    func testBackgroundAfterTheStartLeftKeepsItSent() async throws {
        let outcomes: [(FakeLaundryAPI.Outcome<Bool>, Bool)] = [(.ok(true), false), (.fail(.timedOut), false), (.ok(true), true)]
        for (outcome, cancelled) in outcomes {
            reset()
            try storePaid()
            let front = self.front!
            api.beforeSend = { name in if name == "start" { front.value = false } }
            api.startChecks = [.ok(L.check())]
            api.starts = [outcome]
            api.startThrowsCancellation = cancelled
            api.orders = Array(repeating: .ok(L.order("20")), count: 6)
            let e = try engine()
            let s = try await e.refresh()
            XCTAssertNotNil(s.start, "\(outcome) cancelled: \(cancelled)")
            XCTAssertNotNil(try storedStart())
            if cancelled { XCTAssertEqual(s.start, .pending(at: L.t0.addingTimeInterval(10))) }

            front.value = true
            api.beforeSend = nil
            api.orders = [.ok(L.order("20")), .ok(L.order("20"))]
            _ = try await e.refresh()
            _ = try await e.refresh()
            XCTAssertEqual(api.count("start"), 1)
            XCTAssertEqual(api.count("startCheck"), 1)
        }
    }

    // MARK: account, old records, sample

    /// An order placed by another U净 account is never started.
    func testAnotherAccountNeverStarts() async throws {
        for signedIn in ["acct-2", nil] as [String?] {
            reset()
            try storePaid()
            api.startChecks = [.ok(L.check())]
            api.starts = [.ok(true)]
            let s = try await engine(account: signedIn).refresh()
            XCTAssertEqual(api.count("startCheck"), 0)
            XCTAssertEqual(api.count("start"), 0)
            XCTAssertEqual(s.start, .blocked(.account))
            XCTAssertEqual(LaundryDisplay(s).startLine?.text, "这单是另一个 U净 账号下的，没帮你启动。")
            XCTAssertEqual(LaundryDisplay(s).startLine?.detail, "去那个账号的 U净 App 里启动。")
        }
    }

    func testRecordWithoutAnAccountNeverStarts() async throws {
        try storePaid()
        var c = try XCTUnwrap(try vault.checkout())
        c.accountID = nil
        try vault.saveCheckout(c)
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        _ = try await engine().refresh()
        XCTAssertEqual(api.count("start"), 0)
    }

    func testNormalPaidOrderNeverReadsForAStart() async throws {
        try storePaid(immediate: false)
        api.orders = [.ok(L.order("20"))]
        _ = try await engine().refresh()
        XCTAssertEqual(api.calls, ["order"])
    }

    /// Records from before 立刻洗衣 decode as normal orders.
    func testOldRecordIsANormalOrder() throws {
        try storePaid()
        let data = try JSONEncoder().encode(try XCTUnwrap(try vault.checkout()))
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["immediate"])
        object.removeValue(forKey: "immediate")
        object.removeValue(forKey: "start")
        let old = try JSONDecoder().decode(LaundryCheckout.self, from: try JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.immediate)
        XCTAssertNil(old.start)
        XCTAssertEqual(old.phase, .active)
        XCTAssertEqual(old.orderID, L.orderID)
    }

    func testRelaunchKeepsEveryStartRecord() throws {
        let at = L.t0.addingTimeInterval(30)
        let all: [LaundryStart] = [.sent(at: at), .accepted(at: at), .pending(at: at), .refused(message: "设备未关门", at: at),
                                   .blocked(.expired), .blocked(.unsupported), .started]
        for start in all {
            reset()
            try storePaid(start: start)
            let e = try engine()
            let restored = LaundryReducer.restore(try vault.checkout())
            XCTAssertEqual(restored.start, start)
            XCTAssertTrue(api.calls.isEmpty)
            _ = e
        }
    }

    /// The sample's foreground answer is always "not in front".
    func testSampleIsNeverInFront() async {
        let sampleFront = CampusServices.sample().laundryInFront(live: { true })
        let sample = await sampleFront()
        XCTAssertFalse(sample)
        let liveFront = CampusServices(kind: .live, secureStore: InMemorySecureStore(), defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                        sharedPreferences: nil, schoolHTTP: SampleHTTPClient(), showerHTTP: SampleHTTPClient(),
                                        laundryHTTP: SampleHTTPClient(), feedbackHTTP: nil, showerTransport: SampleShowerTransport(),
                                        leaseFile: nil, applicationSupport: nil, sharedDidChange: {}).laundryInFront(live: { true })
        let live = await liveFront()
        XCTAssertTrue(live)
    }

    /// The sample's own engine: the start never comes up.
    func testSampleImmediateOrderNeverStarts() async throws {
        try storePaid()
        let services = CampusServices.sample()
        let counting = CountingHTTP(inner: services.laundryHTTP)
        let counted = UjingClient(http: counting, device: UjingDevice(mobileID: L.mobileID, userAgent: "x"), token: L.token)
        let e = try LaundryEngine(api: counted, vault: vault, launcher: SamplePaymentLauncher(), accountID: Self.account,
                                  inFront: services.laundryInFront(live: { true }), now: { L.t0.addingTimeInterval(20) },
                                  sleep: { _ in })
        let s = try await e.refresh()
        XCTAssertNil(s.start)
        XCTAssertFalse(counting.names.contains("startCheck"))
        XCTAssertFalse(counting.names.contains("startWasher"))
    }
}

/// Records the log names of the requests handed to `inner`.
final class CountingHTTP: HTTPClient, @unchecked Sendable {
    let inner: any HTTPClient
    private let lock = NSLock()
    private var _names: [String] = []
    init(inner: any HTTPClient) { self.inner = inner }
    var names: [String] { lock.withLock { _names } }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _names.append(request.logName) }
        return try await inner.send(request)
    }
}
