import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// 立刻洗衣's short window after the Alipay launch: the engine may start this account's order
/// out of the front only inside it, and still at most once.
final class LaundryPaymentWindowEngineTests: XCTestCase {
    var store: InMemorySecureStore!
    var vault: StoredLaundryVault!
    var api: FakeLaundryAPI!
    var launcher: FakeLauncher!
    var sleeps: Sleeps!
    var front: FrontSwitch!
    var clock: TestClock!
    var log: RecordingDebugLog!

    override func setUp() {
        store = InMemorySecureStore()
        vault = StoredLaundryVault(store: store)
        api = FakeLaundryAPI()
        launcher = FakeLauncher()
        sleeps = Sleeps()
        front = FrontSwitch(true)
        clock = TestClock(L.t0.addingTimeInterval(10))
        log = RecordingDebugLog()
    }

    func engine(account: String? = "acct-1",
                sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil) throws -> LaundryEngine {
        let sleeps = self.sleeps!, front = self.front!, clock = self.clock!
        return try LaundryEngine(api: api, vault: vault, launcher: launcher, accountID: account,
                                 inFront: { front.value }, now: { clock.now },
                                 sleep: sleep ?? { sleeps.record($0) }, debugLog: log)
    }

    var f2f: PaymentArguments {
        PaymentArguments(.object(["url": .string("alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url="
            + "https%3A%2F%2Fopenauth.alipay.com%2Foauth2%2FpublicAppAuthorize.htm%3Fredirect_uri%3Dhttps%253A%252F%252Fwx.zhinengxiyifang.cn%252Fstatic%252FcommonWasher%252Findex.html")]))
    }

    /// Created and unpaid; `pay()` comes next.
    func created(immediate: Bool, account: String? = "acct-1",
                 sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil) async throws -> LaundryEngine {
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        let e = try engine(account: account, sleep: sleep)
        let s = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard, immediate: immediate)
        XCTAssertEqual(s.phase, .created)
        return e
    }

    func pay(_ e: LaundryEngine) async throws {
        api.methods = [.ok([PayChannel(channel: "alipayF2F", branchType: 0)])]
        api.arguments = [.ok(f2f)]
        let s = try await e.pay()
        XCTAssertEqual(s.phase, .paying)
    }

    var until: Date { clock.now.addingTimeInterval(45) }

    func testWindowAllowsStartWhileNotInFront() async throws {
        let e = try await created(immediate: true)
        let opened = await e.openPaymentWindow(until: until)
        XCTAssertTrue(opened)
        try await pay(e)
        front.value = false
        api.orders = [.ok(L.order("20")), .ok(L.order("40", remain: 1800))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        let s = try await e.returnedFromPayment()
        XCTAssertEqual(api.count("startCheck"), 1)
        XCTAssertEqual(api.count("start"), 1)
        XCTAssertEqual(s.start, .started)
    }

    func testNoStartAfterWindowDeadline() async throws {
        let e = try await created(immediate: true)
        _ = await e.openPaymentWindow(until: until)
        try await pay(e)
        front.value = false
        clock.now = clock.now.addingTimeInterval(46)
        api.orders = [.ok(L.order("20"))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        let s = try await e.returnedFromPayment()
        XCTAssertEqual(api.count("startCheck"), 0)
        XCTAssertEqual(api.count("start"), 0)
        XCTAssertNil(s.start)
        XCTAssertTrue(log.events.contains(.laundryStart(.skipped(.windowClosed))))
    }

    func testWindowRefusedForNormalOrder() async throws {
        let e = try await created(immediate: false)
        let opened = await e.openPaymentWindow(until: until)
        XCTAssertFalse(opened)
    }

    func testWindowRefusedForOtherAccount() async throws {
        _ = try await created(immediate: true)
        let other = try engine(account: "acct-2")
        let opened = await other.openPaymentWindow(until: until)
        XCTAssertFalse(opened)
        let signedOut = try engine(account: nil)
        let none = await signedOut.openPaymentWindow(until: until)
        XCTAssertFalse(none)
    }

    func testWindowRefusedWhenTooLongOrPast() async throws {
        let e = try await created(immediate: true)
        let long = await e.openPaymentWindow(until: clock.now.addingTimeInterval(46))
        XCTAssertFalse(long, "never more than 45 s")
        let past = await e.openPaymentWindow(until: clock.now)
        XCTAssertFalse(past)
    }

    func testWindowRefusedOnceStartTried() async throws {
        let e = try await created(immediate: true)
        try await pay(e)
        api.orders = [.ok(L.order("20")), .ok(L.order("40", remain: 1800))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        _ = try await e.returnedFromPayment()
        let opened = await e.openPaymentWindow(until: until)
        XCTAssertFalse(opened)
    }

    func testClosedWindowSendsNothingAndCloseIsIdempotent() async throws {
        let e = try await created(immediate: true)
        _ = await e.openPaymentWindow(until: until)
        try await pay(e)
        await e.closePaymentWindow()
        await e.closePaymentWindow()
        front.value = false
        api.orders = [.ok(L.order("20"))]
        api.startChecks = [.ok(L.check())]
        let s = try await e.returnedFromPayment()
        XCTAssertEqual(api.count("startCheck"), 0)
        XCTAssertNil(s.start)
    }

    /// Without a window nothing changes: out of the front, no start.
    func testNoWindowStillFrontOnly() async throws {
        let e = try await created(immediate: true)
        try await pay(e)
        front.value = false
        api.orders = [.ok(L.order("20"))]
        _ = try await e.returnedFromPayment()
        XCTAssertEqual(api.count("startCheck"), 0)
        XCTAssertTrue(log.events.contains(.laundryStart(.skipped(.notFront))))
    }

    func testConcurrentRefreshDuringWindowRunIsBusy() async throws {
        let gate = SleepGate()
        let e = try await created(immediate: true, sleep: { _ in await gate.wait() })
        _ = await e.openPaymentWindow(until: until)
        try await pay(e)
        front.value = false
        api.orders = [.ok(L.order("20")), .ok(L.order("40", remain: 1800))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        let run = Task { try await e.returnedFromPayment() }
        await gate.waitUntilWaiting()
        do { _ = try await e.refresh(); XCTFail("expected busy") }
        catch { XCTAssertEqual(error as? LaundryEngineError, .busy) }
        gate.openAll()
        _ = try await run.value
        XCTAssertEqual(api.count("start"), 1)
    }

    func testStartSentOnceAcrossWindowThenForeground() async throws {
        let e = try await created(immediate: true)
        _ = await e.openPaymentWindow(until: until)
        try await pay(e)
        front.value = false
        api.orders = [.ok(L.order("20")), .ok(L.order("20"))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.fail(.timedOut)]
        _ = try await e.returnedFromPayment()
        XCTAssertEqual(api.count("start"), 1)
        front.value = true
        api.orders = [.ok(L.order("20")), .ok(L.order("20"))]
        _ = try await e.refresh()
        _ = try await e.refresh()
        XCTAssertEqual(api.count("start"), 1, "an unknown result is never sent again")
        XCTAssertEqual(api.count("startCheck"), 1)
    }

    /// The window's run is cancelled while it waits between reads: no read goes out after
    /// that, the run ends by itself and the engine is free again.
    func testCancelledPollSendsNoFurtherRead() async throws {
        let counter = SleepCounter()
        let e = try await created(immediate: true, sleep: { _ in
            if counter.next() == 3 { withUnsafeCurrentTask { $0?.cancel() } }
        })
        _ = await e.openPaymentWindow(until: until)
        try await pay(e)
        front.value = false
        let before = api.count("order")
        api.orders = Array(repeating: .ok(L.order("10")), count: 6)
        let s = try await Task { try await e.returnedFromPayment() }.value
        XCTAssertEqual(api.count("order") - before, 2, "the reads after the first two waits only")
        XCTAssertEqual(s.phase, .verifying)
        api.orders = [.ok(L.order("10"))]
        _ = try await e.refresh()
    }
}

/// Counts calls across threads.
final class SleepCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}

/// A sleep that waits until opened.
final class SleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false
    private var waiting = false
    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let go = lock.withLock { () -> Bool in
                if open { return true }
                waiting = true; waiters.append(c); return false
            }
            if go { c.resume() }
        }
    }
    func waitUntilWaiting() async {
        while !lock.withLock({ waiting }) { await Task.yield() }
    }
    func openAll() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            open = true; defer { waiters = [] }; return waiters
        }
        all.forEach { $0.resume() }
    }
}

/// When the window's reads go on: only this account's 立刻洗衣 order, captured at open, in
/// the same engine, inside 45 s, until the start was tried or the order ended.
final class LaundryPaymentWindowTests: XCTestCase {
    let t = L.t0.addingTimeInterval(10)

    func record(_ phase: LaundryPhase = .paying, immediate: Bool = true, account: String = "acct-1") -> LaundryCheckout {
        LaundryCheckout(phase: phase, draft: L.draft, createdAt: L.t0, orderID: L.orderID, order: L.order("10"),
                        accountID: account, immediate: immediate)
    }

    var window: LaundryPaymentWindow { LaundryPaymentWindow(record: record(.created), engineGeneration: 3, now: t)! }

    func testOpensOnlyForImmediateOwnedOrder() {
        XCTAssertNotNil(LaundryPaymentWindow(record: record(.created), engineGeneration: 1, now: t))
        XCTAssertNotNil(LaundryPaymentWindow(record: record(.paying), engineGeneration: 1, now: t))
        XCTAssertNil(LaundryPaymentWindow(record: record(.created, immediate: false), engineGeneration: 1, now: t))
        XCTAssertNil(LaundryPaymentWindow(record: record(.active), engineGeneration: 1, now: t))
        var tried = record(.created); tried.start = .sent(at: t)
        XCTAssertNil(LaundryPaymentWindow(record: tried, engineGeneration: 1, now: t))
        var noAccount = record(.created); noAccount.accountID = nil
        XCTAssertNil(LaundryPaymentWindow(record: noAccount, engineGeneration: 1, now: t))
        XCTAssertEqual(window.until, t.addingTimeInterval(45))
    }

    func testKeepsGoingWhileWaitingForPaymentOrStart() {
        for phase in [LaundryPhase.created, .paying, .verifying] {
            XCTAssertTrue(window.shouldContinue(record(phase), engineGeneration: 3, now: t.addingTimeInterval(10)), "\(phase)")
        }
        var paid = record(.active); paid.order = L.order("20")
        XCTAssertTrue(window.shouldContinue(paid, engineGeneration: 3, now: t.addingTimeInterval(10)))
    }

    func testStopsAfter45Seconds() {
        XCTAssertFalse(window.shouldContinue(record(), engineGeneration: 3, now: t.addingTimeInterval(45)))
    }

    func testStopsOnAccountOrderOrEngineChange() {
        XCTAssertFalse(window.shouldContinue(record(account: "acct-2"), engineGeneration: 3, now: t))
        var other = record(); other.orderID = "TESTORDER0002"
        XCTAssertFalse(window.shouldContinue(other, engineGeneration: 3, now: t))
        var later = record(); later.createdAt = L.t0.addingTimeInterval(1)
        XCTAssertFalse(window.shouldContinue(later, engineGeneration: 3, now: t))
        XCTAssertFalse(window.shouldContinue(record(), engineGeneration: 4, now: t))
        XCTAssertFalse(window.shouldContinue(nil, engineGeneration: 3, now: t))
    }

    func testStopsOnceStartTried() {
        var r = record(.active); r.order = L.order("20"); r.start = .sent(at: t)
        XCTAssertFalse(window.shouldContinue(r, engineGeneration: 3, now: t))
        r.start = .accepted(at: t)
        XCTAssertFalse(window.shouldContinue(r, engineGeneration: 3, now: t))
    }

    func testStopsWhenLaunchFailedOrRefused() {
        for notice in [LaundryNotice.launchFailed, .launchRefused(.disallowedLink), .noPayChannel] {
            var r = record(.created); r.notice = notice
            XCTAssertFalse(window.shouldContinue(r, engineGeneration: 3, now: t), "\(notice)")
        }
    }

    func testStopsWhenWashingOrEnded() {
        var washing = record(.active); washing.order = L.order("40", remain: 1800)
        XCTAssertFalse(window.shouldContinue(washing, engineGeneration: 3, now: t))
        for phase in [LaundryPhase.none, .cancelling, .attention] {
            XCTAssertFalse(window.shouldContinue(record(phase), engineGeneration: 3, now: t), "\(phase)")
        }
        var done = record(.active); done.order = L.order("50")
        XCTAssertFalse(window.shouldContinue(done, engineGeneration: 3, now: t))
    }
}
