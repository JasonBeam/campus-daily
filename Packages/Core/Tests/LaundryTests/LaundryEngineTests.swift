import XCTest
import Foundation
@testable import Core

/// Scripted U净 API. Every call is recorded; results are consumed in order. `onCreate` etc.
/// see the vault at the moment the request would leave.
final class FakeLaundryAPI: LaundryOrdering, @unchecked Sendable {
    // @unchecked: state guarded by `lock`.
    enum Outcome<T: Sendable>: Sendable { case ok(T), fail(ServiceError) }
    private let lock = NSLock()
    private var _calls: [String] = []
    var scans: [Outcome<WasherScan>] = []
    var creates: [Outcome<String>] = []
    var orders: [Outcome<LaundryOrder>] = []
    var methods: [Outcome<[PayChannel]>] = []
    var arguments: [Outcome<PaymentArguments>] = []
    var cancels: [Outcome<Bool>] = []
    var beforeSend: (@Sendable (String) -> Void)?

    var calls: [String] { lock.withLock { _calls } }
    func count(_ name: String) -> Int { calls.filter { $0 == name }.count }

    private func take<T>(_ name: String, _ list: ReferenceWritableKeyPath<FakeLaundryAPI, [Outcome<T>]>) throws -> T {
        beforeSend?(name)
        let o: Outcome<T>? = lock.withLock {
            _calls.append(name)
            return self[keyPath: list].isEmpty ? nil : self[keyPath: list].removeFirst()
        }
        switch o {
        case .ok(let v)?: return v
        case .fail(let e)?: throw e
        case nil: throw ServiceError.timedOut
        }
    }

    func scan(qr: String) async throws -> WasherScan { try take("scan", \.scans) }
    func createOrder(_ request: OrderRequest) async throws -> String { try take("create", \.creates) }
    func order(_ id: String) async throws -> LaundryOrder { try take("order", \.orders) }
    func paymentMethods(_ id: String) async throws -> [PayChannel] { try take("methods", \.methods) }
    func paymentArguments(_ id: String, channel: PayChannel) async throws -> PaymentArguments { try take("arguments", \.arguments) }
    func cancel(_ id: String) async throws { _ = try take("cancel", \.cancels) }
}

final class FakeLauncher: PaymentLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [PayLaunch] = []
    var result = true
    var opened: [PayLaunch] { lock.withLock { _opened } }
    func open(_ launch: PayLaunch) async -> Bool { lock.withLock { _opened.append(launch); return result } }
}

final class RecordingHooks: LaundryHooks, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    var events: [String] { lock.withLock { _events } }
    func updateActivity(_ plan: LaundryActivityPlan) async { lock.withLock { _events.append("update:\(plan.endsAt != nil)") } }
    func endActivity() async { lock.withLock { _events.append("end") } }
    func diagnostic(_ event: String) async { lock.withLock { _events.append(event) } }
}

/// Vault whose checkout writes fail when `failWhen` matches.
final class FlakyLaundryVault: LaundryVault, @unchecked Sendable {
    let inner: StoredLaundryVault
    var failWhen: @Sendable (LaundryCheckout?) -> Bool
    init(inner: StoredLaundryVault, failWhen: @escaping @Sendable (LaundryCheckout?) -> Bool) { self.inner = inner; self.failWhen = failWhen }
    func accountItem() throws -> UjingAccountItem? { try inner.accountItem() }
    func saveAccountItem(_ item: UjingAccountItem?) throws { try inner.saveAccountItem(item) }
    func checkout() throws -> LaundryCheckout? { try inner.checkout() }
    func saveCheckout(_ checkout: LaundryCheckout?) throws {
        if failWhen(checkout) { throw StorageError(operation: "write laundry.checkout", status: -1) }
        try inner.saveCheckout(checkout)
    }
}

final class Sleeps: @unchecked Sendable {
    private let lock = NSLock()
    private var _delays: [TimeInterval] = []
    var delays: [TimeInterval] { lock.withLock { _delays } }
    func record(_ d: TimeInterval) { lock.withLock { _delays.append(d) } }
}

final class LaundryEngineTests: XCTestCase {
    var store: InMemorySecureStore!
    var vault: StoredLaundryVault!
    var api: FakeLaundryAPI!
    var launcher: FakeLauncher!
    var hooks: RecordingHooks!
    var sleeps: Sleeps!

    override func setUp() {
        store = InMemorySecureStore()
        vault = StoredLaundryVault(store: store)
        api = FakeLaundryAPI()
        launcher = FakeLauncher()
        hooks = RecordingHooks()
        sleeps = Sleeps()
    }

    func engine(vault v: LaundryVault? = nil, at offset: TimeInterval = 10) throws -> LaundryEngine {
        let sleeps = self.sleeps!
        let t = L.t0.addingTimeInterval(offset)
        return try LaundryEngine(api: api, vault: v ?? vault, launcher: launcher, hooks: hooks,
                                 now: { t }, sleep: { sleeps.record($0) })
    }

    var f2f: PaymentArguments {
        PaymentArguments(.object(["url": .string("alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url="
            + "https%3A%2F%2Fopenauth.alipay.com%2Foauth2%2FpublicAppAuthorize.htm%3Fredirect_uri%3Dhttps%253A%252F%252Fwx.zhinengxiyifang.cn%252Fstatic%252FcommonWasher%252Findex.html")]))
    }

    /// Engine with a created, unpaid order.
    func createdEngine() async throws -> LaundryEngine {
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        let e = try engine()
        let s = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        XCTAssertEqual(s.phase, .created)
        return e
    }

    // MARK: create

    /// While a reset runs no order is created; nothing is sent or recorded.
    func testNoOrderWhileAResetRuns() async throws {
        let marker = ResetMarker(store: InMemorySecureStore())
        let t = L.t0.addingTimeInterval(10)
        try marker.begin(at: t)
        let sleeps = self.sleeps!
        let e = try LaundryEngine(api: api, vault: vault, launcher: launcher, hooks: hooks, resetMarker: marker,
                                  now: { t }, sleep: { sleeps.record($0) })
        do { _ = try await e.confirmOrder(L.snapshot(), program: L.standard); XCTFail("expected the refusal") }
        catch { XCTAssertEqual(error as? AppReset.InProgress, AppReset.InProgress()) }
        XCTAssertEqual(api.calls, [])
        XCTAssertNil(try vault.checkout())
    }

    func testConfirmPersistsBeforeCreateAndCreatesOnce() async throws {
        let v = vault!
        api.beforeSend = { name in
            if name == "create" { XCTAssertEqual(try? v.checkout()?.phase, .creating) }
        }
        let e = try await createdEngine()
        XCTAssertEqual(api.calls, ["create", "order"])
        let stored = try XCTUnwrap(try vault.checkout())
        XCTAssertEqual(stored.phase, .created)
        XCTAssertEqual(stored.orderID, L.orderID)
        let state = await e.state
        XCTAssertTrue(state.canPay)
        do { _ = try await e.confirmOrder(L.snapshot(), program: L.standard); XCTFail() }
        catch { XCTAssertEqual(error as? LaundryEngineError, .notAllowed) }
        XCTAssertEqual(api.count("create"), 1)
    }

    func testStaleOrChangedWasherNeverCreates() async throws {
        let e = try engine(at: 100)
        do { _ = try await e.confirmOrder(L.snapshot(), program: L.standard); XCTFail() }
        catch { XCTAssertEqual(error as? LaundryEngineError, .washerChanged) }
        XCTAssertTrue(api.calls.isEmpty)
        XCTAssertNil(try vault.checkout())
    }

    func testStorageFailureBeforeCreateSendsNothing() async throws {
        let flaky = FlakyLaundryVault(inner: vault) { $0?.phase == .creating }
        let e = try engine(vault: flaky)
        do { _ = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard); XCTFail() }
        catch { XCTAssertEqual(error as? LaundryEngineError, .storage) }
        XCTAssertTrue(api.calls.isEmpty)
        do { _ = try await e.refresh(); XCTFail() }
        catch { XCTAssertEqual(error as? LaundryEngineError, .storage) }
    }

    func testCreateUncertainReconcilesWithoutSecondCreate() async throws {
        api.creates = [.fail(.uncertain(.ujing))]
        api.scans = [.ok(WasherScan(deviceID: L.device, moduleType: 7, status: 11, createOrderEnabled: false, activeOrderID: L.orderID))]
        api.orders = [.ok(L.order("10"))]
        let e = try engine()
        let s = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        XCTAssertEqual(api.calls, ["create", "scan", "order"])
        XCTAssertEqual(s.phase, .created)
        XCTAssertEqual(s.orderID, L.orderID)
    }

    func testCreateRefusedClears() async throws {
        let refusal = ServiceError.rejected(.ujing, code: "30010", message: "设备正在使用中")
        api.creates = [.fail(refusal)]
        let e = try engine()
        let s = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        XCTAssertEqual(s.phase, .none)
        XCTAssertEqual(s.notice, .refused(refusal))
        XCTAssertNil(try vault.checkout())
    }

    // MARK: pay

    func testPayOnceLaunchThenVerifyUntilWashing() async throws {
        let e = try await createdEngine()
        api.methods = [.ok([PayChannel(channel: "alipayF2F", branchType: 0)])]
        api.arguments = [.ok(f2f)]
        let v = vault!
        api.beforeSend = { name in
            if name == "arguments" { XCTAssertEqual(try? v.checkout()?.phase, .paying) }
        }
        var s = try await e.pay()
        XCTAssertEqual(s.phase, .paying)
        XCTAssertEqual(launcher.opened.count, 1)
        guard case .checkout? = launcher.opened.first else { return XCTFail() }
        XCTAssertEqual(api.count("arguments"), 1)

        api.orders = [.ok(L.order("10")), .ok(L.order("20")), .ok(L.order("40", remain: 1800))]
        s = try await e.returnedFromPayment()
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(sleeps.delays, [2, 4])
        s = try await e.refresh()
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(hooks.events, ["update:true"])
        XCTAssertEqual(api.count("arguments"), 1)

        api.orders = [.ok(L.order("50"))]
        s = try await e.refresh()
        XCTAssertEqual(s.phase, .none)
        XCTAssertEqual(s.lastOutcome?.status.code, "50")
        XCTAssertEqual(hooks.events.last, "end")
        XCTAssertEqual(try vault.checkout()?.lastOutcome?.status.code, "50")
    }

    func testRefusedLaunchNeverOpensAlipay() async throws {
        let e = try await createdEngine()
        api.methods = [.ok([PayChannel(channel: "alipay")])]
        api.arguments = [.ok(PaymentArguments(.object(["payInfo": .object(["orderInfo": .string(
            "method=alipay.trade.app.pay&biz_content=%7B%22total_amount%22%3A%220.01%22%7D")])])))]
        let s = try await e.pay()
        XCTAssertEqual(s.phase, .created)
        XCTAssertEqual(s.notice, .launchRefused(.amountMismatch))
        XCTAssertTrue(launcher.opened.isEmpty)
        XCTAssertEqual(hooks.events, ["pay.launchRefused.amountMismatch"])
        do { _ = try await e.pay(); XCTFail() } catch { XCTAssertEqual(error as? LaundryEngineError, .notAllowed) }
        XCTAssertEqual(api.count("arguments"), 1)
    }

    func testPaymentUncertainPollsNeverRetries() async throws {
        let e = try await createdEngine()
        api.methods = [.ok([PayChannel(channel: "alipay")])]
        api.arguments = [.fail(.timedOut)]
        api.orders = Array(repeating: .ok(L.order("10")), count: 6)
        let s = try await e.pay()
        XCTAssertEqual(s.phase, .created)
        XCTAssertEqual(s.notice, .paymentNotConfirmed)
        XCTAssertEqual(sleeps.delays, LaundryCheckout.pollDelays)
        XCTAssertEqual(api.count("arguments"), 1)
        XCTAssertTrue(launcher.opened.isEmpty)
        XCTAssertFalse(s.canPay)
    }

    func testLauncherFailureKeepsRecord() async throws {
        let e = try await createdEngine()
        launcher.result = false
        api.methods = [.ok([PayChannel(channel: "alipayF2F", branchType: 0)])]
        api.arguments = [.ok(f2f)]
        let s = try await e.pay()
        XCTAssertEqual(s.phase, .created)
        XCTAssertEqual(s.notice, .launchFailed)
        XCTAssertNotNil(try vault.checkout()?.paymentRequestedAt)
    }

    // MARK: cancel

    func testCancelPreReadOnePostThenRead() async throws {
        let e = try await createdEngine()
        api.orders = [.ok(L.order("10")), .ok(L.order("53"))]
        api.cancels = [.ok(true)]
        let s = try await e.cancel()
        XCTAssertEqual(api.calls.suffix(3), ["order", "cancel", "order"])
        XCTAssertEqual(s.phase, .none)
        XCTAssertEqual(s.lastOutcome?.status.code, "53")
    }

    func testCancelUncertainNeverPostsAgain() async throws {
        let e = try await createdEngine()
        api.orders = [.ok(L.order("10"))] + Array(repeating: .ok(L.order("10")), count: 6)
        api.cancels = [.fail(.timedOut)]
        let s = try await e.cancel()
        XCTAssertEqual(api.count("cancel"), 1)
        XCTAssertEqual(s.phase, .cancelling)
        XCTAssertEqual(s.notice, .cancelUnconfirmed)
        XCTAssertTrue(s.cancelSent)
        do { _ = try await e.cancel(); XCTFail() } catch { XCTAssertEqual(error as? LaundryEngineError, .notAllowed) }
    }

    // MARK: relaunch

    func testRelaunchFromCreatingReconcilesOnly() async throws {
        let creating = LaundryReducer.reduce(.empty, .confirm(L.draft, at: L.t0)).0
        try vault.saveCheckout(creating)
        let e = try engine()
        let restored = await e.state
        XCTAssertEqual(restored.phase, .reconcile)
        XCTAssertEqual(try vault.checkout()?.phase, .reconcile)
        XCTAssertTrue(api.calls.isEmpty, "nothing is sent at relaunch")
        api.scans = [.ok(WasherScan(deviceID: L.device, moduleType: 7, status: 0, createOrderEnabled: true, activeOrderID: nil))]
        let s = try await e.refresh()
        XCTAssertEqual(api.calls, ["scan"])
        XCTAssertEqual(s.notice, .orderNotFound)
        let cleared = try await e.resolveManually()
        XCTAssertEqual(cleared.phase, .none)
        XCTAssertNil(try vault.checkout())
        XCTAssertEqual(api.count("create"), 0)
    }

    func testRelaunchFromPayingVerifiesOnly() async throws {
        var paying = LaundryReducer.reduce(.empty, .confirm(L.draft, at: L.t0)).0
        paying = LaundryReducer.reduce(paying, .created(orderID: L.orderID)).0
        paying = LaundryReducer.reduce(paying, .orderRead(L.order("10"), at: L.t0)).0
        paying = LaundryReducer.reduce(paying, .paymentMethods([PayChannel(channel: "alipay")], at: L.t0)).0
        XCTAssertEqual(paying.phase, .paying)
        try vault.saveCheckout(paying)
        let e = try engine()
        let restored = await e.state
        XCTAssertEqual(restored.phase, .verifying)
        XCTAssertTrue(api.calls.isEmpty)
        api.orders = [.ok(L.order("20"))]
        let s = try await e.refresh()
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(api.calls, ["order"])
    }

    func testRelaunchFromSentCancelKeepsCancelling() async throws {
        var c = LaundryReducer.reduce(.empty, .confirm(L.draft, at: L.t0)).0
        c = LaundryReducer.reduce(c, .created(orderID: L.orderID)).0
        c = LaundryReducer.reduce(c, .orderRead(L.order("10"), at: L.t0)).0
        c = LaundryReducer.reduce(c, .cancel).0
        c = LaundryReducer.reduce(c, .orderRead(L.order("10"), at: L.t0)).0
        XCTAssertTrue(c.cancelSent)
        try vault.saveCheckout(c)
        let e = try engine()
        api.orders = [.ok(L.order("53"))]
        let s = try await e.refresh()
        XCTAssertEqual(api.calls, ["order"])
        XCTAssertEqual(s.phase, .none)
    }

    func testUnreadableRecordFailsClosed() throws {
        let flaky = FailingReadVault()
        XCTAssertThrowsError(try engine(vault: flaky)) { XCTAssertEqual($0 as? LaundryEngineError, .storage) }
    }

    // MARK: vault

    func testMobileIDCreatedOnceAndKeptAcrossLogout() throws {
        let id = try vault.mobileID(make: { L.mobileID })
        XCTAssertEqual(id, L.mobileID)
        XCTAssertEqual(try vault.mobileID(make: { "other" }), L.mobileID)
        try vault.saveAccountItem(UjingAccountItem(mobileID: id, account: UjingAccount(id: "10001", userId: "20002", token: L.token)))
        XCTAssertEqual(try vault.accountItem()?.account?.token, L.token)
        try vault.saveAccountItem(UjingAccountItem(mobileID: id))
        XCTAssertEqual(try vault.mobileID(make: { "other" }), L.mobileID)
        XCTAssertFalse("\(try XCTUnwrap(try vault.accountItem()))".contains(L.mobileID))
    }
}

final class FailingReadVault: LaundryVault, @unchecked Sendable {
    func accountItem() throws -> UjingAccountItem? { nil }
    func saveAccountItem(_ item: UjingAccountItem?) throws {}
    func checkout() throws -> LaundryCheckout? { throw StorageError(operation: "read laundry.checkout", status: -1) }
    func saveCheckout(_ checkout: LaundryCheckout?) throws {}
}
