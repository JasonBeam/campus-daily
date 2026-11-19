import Combine
import XCTest
import Core
import UIKit
@testable import XiaoRiChang

/// The foreground order poll on the live laundry model, fake stores and a scripted U净, with a
/// host that rebuilds the polling task whenever its identity changes, as SwiftUI's
/// `.task(id:)` does. A start the poll's own read leads to is not cancelled by its own
/// progress; leaving the front before `control/start` is handed over sends none, after it at
/// most the one; a failed read waits 30 s.
@MainActor
final class LaundryPollLifecycleTests: XCTestCase {
    /// Paid (20), 立刻洗衣, the pre-start read allows a start, the app stays in front. The gate
    /// right before `control/start` is held until the page has the stored `.sent` and the host
    /// has seen it, then let go: the task carries on, one start goes out, the task is never
    /// rebuilt (no nil/sent round trip).
    func testAStartIsNotCancelledByItsOwnProgress() async {
        let ujing = PollUjing()
        let front = HeldFront { ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)) > 0 }
        let world = PollWorld(record: PollFixture.paid(), ujing: ujing, front: front)
        let laundry = await world.launch()
        let host = PollHost(laundry: laundry, remindersOn: false)
        defer { host.stop() }

        await waitFor { front.isHeld }
        XCTAssertTrue(front.isHeld, "the read reached the gate before control/start")
        await waitFor { laundry.checkout?.start?.isSent == true }
        XCTAssertEqual(laundry.checkout?.start?.isSent, true, "the page has the stored .sent")
        await pause(200)  // the host handles the change
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 0, "not handed over yet")
        front.release()

        await waitFor(seconds: 8) { laundry.checkout?.start == .started }
        XCTAssertEqual(laundry.checkout?.start, .started, "sent, then read washing")
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1)
        XCTAssertEqual(host.rebuilds, 0, "the task running the read was never cancelled")
        XCTAssertEqual(host.identities.count, 1, "no rebuild on the start record")

        await pause(1500)  // the poll goes on: nothing is started again
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1)
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)), 1)
    }

    /// The app leaves the front while `.sent` is stored but the request not handed over: nothing
    /// is sent and the record goes back to "not tried". Back in front it is started once; a
    /// relaunch starts nothing more.
    func testLeavingTheFrontBeforeTheRequestSendsNone() async {
        let ujing = PollUjing()
        let front = HeldFront { ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)) > 0 }
        let world = PollWorld(record: PollFixture.paid(), ujing: ujing, front: front)
        let laundry = await world.launch()
        let host = PollHost(laundry: laundry, remindersOn: false)
        defer { host.stop() }

        await waitFor { front.isHeld && laundry.checkout?.start?.isSent == true }
        XCTAssertEqual(laundry.checkout?.start?.isSent, true)
        front.inFront = false
        host.inFront = false
        front.release()
        await waitFor { !laundry.checkoutBusy && laundry.checkout?.start == nil }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 0, "nothing handed over")
        XCTAssertNil(laundry.checkout?.start, "still to be tried")
        XCTAssertNil(try world.vault.checkout()?.start, "stored as not tried")

        front.inFront = true
        host.inFront = true
        await waitFor(seconds: 8) { laundry.checkout?.start == .started }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1, "started once back in front")
        host.stop()

        let relaunched = await world.launch()
        await relaunched.readOrderAtLaunch()
        let again = PollHost(laundry: relaunched, remindersOn: true)
        defer { again.stop() }
        await pause(1500)
        await waitFor { !relaunched.checkoutBusy }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1, "never a second start")
    }

    /// The app leaves the front after `control/start` was handed over and the answer is lost:
    /// that one request stays the only one, back in front, on a read and after a relaunch.
    func testLeavingTheFrontAfterTheRequestNeverResends() async {
        let ujing = PollUjing()
        ujing.holdStart = true
        let front = HeldFront { false }
        let world = PollWorld(record: PollFixture.paid(), ujing: ujing, front: front)
        let laundry = await world.launch()
        let host = PollHost(laundry: laundry, remindersOn: false)
        defer { host.stop() }

        await waitFor { ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)) > 0 }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1, "handed over")
        front.inFront = false
        host.inFront = false
        ujing.releaseStart()
        await waitFor { !laundry.checkoutBusy && laundry.checkout?.start?.isSent == false }
        if case .pending? = laundry.checkout?.start {} else { XCTFail("unclear answer kept: \(String(describing: laundry.checkout?.start))") }

        front.inFront = true
        host.inFront = true
        await pause(1500)
        await laundry.refreshOrder()  // the scene comes to the front
        await waitFor { !laundry.checkoutBusy }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1, "not again back in front")
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)), 1)
        host.stop()

        let relaunched = await world.launch()
        await relaunched.readOrderAtLaunch()
        let again = PollHost(laundry: relaunched, remindersOn: true)
        defer { again.stop() }
        await pause(1500)
        await waitFor { !relaunched.checkoutBusy }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1, "not again after a relaunch")
        XCTAssertNotNil(relaunched.checkout?.start)
    }

    /// The pre-start read keeps failing (U净 unreachable, left as a notice on the record): over
    /// 95 seconds of every-second ticks the poll reads at 0, 30, 60 and 90 only.
    func testAFailedPreStartReadWaits30Seconds() async {
        let ujing = PollUjing()
        ujing.startCheckFails = true
        let world = PollWorld(record: PollFixture.paid(), ujing: ujing, front: HeldFront { false })
        let laundry = await world.launch()
        let clock = TickClock(start: Date(), ticks: 95)

        await LaundryOrderPoller(laundry: laundry, remindersOn: { false }, now: { clock.now }, tick: clock.tick).run()

        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)), 4, "one read per 30 s")
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 0)
        XCTAssertNil(laundry.checkout?.start)
        XCTAssertNotNil(laundry.checkoutIssue, "the failure is said")
    }

    /// The order read of a normal order fails while the done reminder is on: still every 30 s,
    /// and nothing is started.
    func testAFailedReminderReadWaits30Seconds() async {
        let ujing = PollUjing()
        ujing.detailFails = true
        let world = PollWorld(record: PollFixture.paid(immediate: false), ujing: ujing, front: HeldFront { false })
        let laundry = await world.launch()
        let clock = TickClock(start: Date(), ticks: 95)

        await LaundryOrderPoller(laundry: laundry, remindersOn: { true }, now: { clock.now }, tick: clock.tick).run()

        XCTAssertEqual(ujing.count(UjingEndpoints.detail(PollFixture.orderID)), 3, "at 30, 60 and 90 s")
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)), 0, "a normal order is never started")
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 0)
    }

    /// The record can't be written (blocked at launch): every read the poll asks for fails at
    /// once, without a request. While the payment is still being checked it is tried every 30 s,
    /// not every second, and nothing is sent.
    func testAFailedWriteIsTriedEvery30Seconds() async {
        let ujing = PollUjing()
        let world = PollWorld(record: PollFixture.paid(phase: .paying), ujing: ujing, front: HeldFront { false })
        world.store.failCheckoutWrites = true
        let laundry = await world.launch()
        XCTAssertTrue(laundry.storageBlocked)
        XCTAssertEqual(laundry.checkout?.phase, .verifying)
        var reads = 0
        let watch = laundry.$checkoutBusy.removeDuplicates().sink { if $0 { reads += 1 } }
        defer { watch.cancel() }
        let clock = TickClock(start: Date(), ticks: 95)

        await LaundryOrderPoller(laundry: laundry, remindersOn: { false }, now: { clock.now }, tick: clock.tick).run()

        XCTAssertEqual(reads, 4, "tried at 0, 30, 60 and 90 s")
        XCTAssertEqual(ujing.count(UjingEndpoints.detail(PollFixture.orderID)), 0)
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)), 0)
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 0)
    }

    /// `.sent` can't be stored: `control/start` is not sent.
    func testAStartThatCantBeStoredIsNotSent() async {
        let ujing = PollUjing()
        let world = PollWorld(record: PollFixture.paid(), ujing: ujing, front: HeldFront { false })
        let laundry = await world.launch()
        world.store.failCheckoutWrites = true
        let host = PollHost(laundry: laundry, remindersOn: false)
        defer { host.stop() }

        await waitFor { ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)) > 0 && !laundry.checkoutBusy }
        await pause(1500)
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)), 1)
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 0, "not stored as sent: not sent")
        XCTAssertTrue(laundry.storageBlocked)
    }
}

extension LaundryPollLifecycleTests {
    /// While 立刻洗衣's window runs, the scene's poll and other reads yield to it (`refreshOrder`
    /// skips them); once it ends they read again and the order is started once.
    func testPollerYieldsWhileWindowActiveThenResumes() async {
        let ujing = PollUjing()
        let runner = LaundryPaymentWindowRunner(system: .init(begin: { _ in UIBackgroundTaskIdentifier(rawValue: 1) },
                                                              end: { _ in },
                                                              sleep: { try await Task.sleep(for: .seconds($0)) }))
        let world = PollWorld(record: PollFixture.paid(), ujing: ujing, front: HeldFront { false }, paymentWindow: runner)
        let laundry = await world.launch()
        // Begun once the engine is built (a rebuild ends any window).
        XCTAssertTrue(runner.start(tick: { true }, onStop: {}))
        let host = PollHost(laundry: laundry, remindersOn: false)
        defer { host.stop(); runner.stop() }

        await pause(300)
        XCTAssertEqual(ujing.count(UjingEndpoints.detail(PollFixture.orderID)), 0, "the poll yields")
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(PollFixture.orderID)), 0)
        let skipped = await laundry.refreshOrder()
        XCTAssertEqual(skipped, .skipped, "the scene's read yields too")

        runner.stop()
        await waitFor(seconds: 8) { laundry.checkout?.start == .started }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1)
        await pause(300)
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(PollFixture.orderID)), 1)
    }
}

// MARK: - Fixtures

private enum PollFixture {
    static let orderID = "TESTORDER0001"
    static let accountID = "test-account-1"
    static let device = "test-device-0001"
    static let qr = "https://q.ujing.com.cn/ucqrc/index.html?cd=000000000000000001"
    static let program = WasherProgram(id: 1, name: "标准洗", minutes: 45, price: Money(fen: 400))

    /// Confirmed a minute ago by the signed-in account, paid (20), no start tried.
    static func paid(immediate: Bool = true, phase: LaundryPhase = .active) -> LaundryCheckout {
        let draft = LaundryDraft(deviceID: device, qrCode: qr, machineName: "测试洗衣机01", program: program,
                                 request: OrderRequest(deviceID: device, deviceTypeID: 1, storeID: "test-store-01", programID: 1))
        let order = LaundryOrder(id: orderID, deviceID: device, status: LaundryOrderStatus("20"), paid: true, programID: 1,
                                 createdAt: "2026-10-30T12:00:05+08:00", price: Money(fen: 400))
        let now = Date()
        return LaundryCheckout(phase: phase, draft: draft, createdAt: now.addingTimeInterval(-60), orderID: orderID, order: order,
                               orderReadAt: now.addingTimeInterval(-30), paymentRequestedAt: now.addingTimeInterval(-50),
                               accountID: accountID, paidAt: now.addingTimeInterval(-30), waitingSince: now.addingTimeInterval(-30),
                               immediate: immediate)
    }
}

/// One phone: its Keychain and settings, kept across launches.
@MainActor private final class PollWorld {
    let store = FailingStore()
    let defaults = SampleDefaults()
    let ujing: PollUjing
    let front: HeldFront
    var vault: StoredLaundryVault { StoredLaundryVault(store: store) }

    let paymentWindow: LaundryPaymentWindowRunner?

    init(record: LaundryCheckout, ujing: PollUjing, front: HeldFront, paymentWindow: LaundryPaymentWindowRunner? = nil) {
        self.ujing = ujing; self.front = front; self.paymentWindow = paymentWindow
        try! vault.saveAccountItem(UjingAccountItem(mobileID: "00000000-0000-4000-8000-000000000001",
                                                    account: UjingAccount(id: PollFixture.accountID, userId: "1", token: "test-token")))
        try! vault.saveCheckout(record)
        defaults.set(try! JSONEncoder().encode([SavedWasher(id: PollFixture.device, qrCode: PollFixture.qr, name: "楼下")]),
                     forKey: PreferenceKey.laundryMachines)
    }

    /// The live laundry model as a launch builds it, once it has the stored record.
    func launch() async -> LaundryModel {
        let services = CampusServices(kind: .live, secureStore: store, defaults: defaults, sharedPreferences: nil,
                                      schoolHTTP: SampleHTTPClient(), showerHTTP: SampleHTTPClient(), laundryHTTP: ujing,
                                      feedbackHTTP: nil, showerTransport: SampleShowerTransport(), leaseFile: nil,
                                      applicationSupport: nil, sharedDidChange: {})
        let front = front
        let laundry = LaundryModel(services: services, reminders: Reminders.sample(defaults: defaults), activities: nil,
                                   inFront: { await front.check() },
                                   paymentWindow: paymentWindow ?? LaundryPaymentWindowRunner())
        await waitFor { laundry.checkout != nil }
        return laundry
    }
}

/// Stands in for the scene's `.task(id: laundry.pollIdentity(...))`: whenever the identity
/// changes it cancels the running task and starts a new one, after the change is published.
@MainActor private final class PollHost {
    let laundry: LaundryModel
    let remindersOn: Bool
    var inFront = true { didSet { reconcile() } }
    private(set) var identities: [LaundryForegroundPoll.Identity] = []
    /// Running tasks cancelled for a new identity.
    private(set) var rebuilds = 0
    private var task: Task<Void, Never>?
    private var watch: AnyCancellable?
    private var stopped = false

    init(laundry: LaundryModel, remindersOn: Bool) {
        self.laundry = laundry; self.remindersOn = remindersOn
        watch = laundry.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        reconcile()
    }

    private func reconcile() {
        guard !stopped else { return }
        let identity = laundry.pollIdentity(inFront: inFront)
        guard identity != identities.last else { return }
        identities.append(identity)
        if let task { task.cancel(); rebuilds += 1 }
        guard inFront else { task = nil; return }
        let poller = LaundryOrderPoller(laundry: laundry, remindersOn: { [remindersOn] in remindersOn },
                                        tick: { try await Task.sleep(for: .milliseconds(20)) })
        task = Task { await poller.run() }
    }

    func stop() { stopped = true; watch?.cancel(); task?.cancel(); task = nil }
}

/// Whether the app is in front, as the engine asks it; the first ask for which `holdWhen` is
/// true waits until `release`.
private final class HeldFront: @unchecked Sendable {
    private let lock = NSLock()
    private var _inFront = true
    private var held = false
    private var used = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var released = false
    private let holdWhen: @Sendable () -> Bool

    init(holdWhen: @escaping @Sendable () -> Bool) { self.holdWhen = holdWhen }

    var inFront: Bool {
        get { lock.withLock { _inFront } }
        set { lock.withLock { _inFront = newValue } }
    }
    var isHeld: Bool { lock.withLock { held } }

    func check() async -> Bool {
        let hold = lock.withLock { () -> Bool in
            guard !used, holdWhen() else { return false }
            used = true
            return true
        }
        if hold {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let resume = lock.withLock { () -> Bool in
                    if released { return true }
                    held = true; waiter = c
                    return false
                }
                if resume { c.resume() }
            }
        }
        return inFront
    }

    func release() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true; held = false
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume()
    }
}

/// U净 for one paid order. The order reads 20 until a start was asked for, then washing; the
/// pre-start read allows a start. Order reads or pre-start reads can be made to fail, and the
/// start can be held until `releaseStart` (it then ends offline: the answer is lost).
private final class PollUjing: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private var _holdStart = false
    private var _startCheckFails = false
    private var _detailFails = false
    private let held: AsyncStream<Void>
    private let go: AsyncStream<Void>.Continuation
    private let id = PollFixture.orderID

    init() { (held, go) = AsyncStream<Void>.makeStream() }

    var holdStart: Bool { get { lock.withLock { _holdStart } } set { lock.withLock { _holdStart = newValue } } }
    var startCheckFails: Bool { get { lock.withLock { _startCheckFails } } set { lock.withLock { _startCheckFails = newValue } } }
    var detailFails: Bool { get { lock.withLock { _detailFails } } set { lock.withLock { _detailFails = newValue } } }

    func count(_ path: String) -> Int { lock.withLock { paths.filter { $0 == path }.count } }
    func releaseStart() { go.yield(); go.finish() }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let path = request.url.path
        let started = lock.withLock { () -> Bool in
            paths.append(path)
            return paths.contains(UjingEndpoints.startWasher(id))
        }
        switch path {
        case UjingEndpoints.detail(id):
            if detailFails { throw ServiceError.offline }
            return reply(order(status: started ? 40 : 20, extra: started ? #","remainTime":2400"# : ""))
        case UjingEndpoints.startCheck(id):
            if startCheckFails { throw ServiceError.offline }
            return reply(order(status: 20, extra: #","moduleType":7,"online":1,"selfCleanEnable":0,"selfCleanPrice":0"#))
        case UjingEndpoints.startWasher(id):
            if holdStart {
                for await _ in held { break }
                throw ServiceError.offline
            }
            return reply(#"{"errorMessage":""}"#)
        default:
            throw ServiceError.offline
        }
    }

    private func order(status: Int, extra: String) -> String {
        #"{"orderId":"\#(id)","deviceId":"\#(PollFixture.device)","status":\#(status),"payFlag":1,"#
            + #""deviceWashModelId":1,"createAt":"2026-10-30T12:00:05+08:00","payPrice":4\#(extra)}"#
    }

    private func reply(_ data: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": "application/json"],
                     body: Data(#"{"code":0,"message":"success","data":\#(data)}"#.utf8))
    }
}

/// A Keychain in memory whose laundry record writes can be made to fail.
private final class FailingStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var _failCheckoutWrites = false
    var failCheckoutWrites: Bool {
        get { lock.withLock { _failCheckoutWrites } }
        set { lock.withLock { _failCheckoutWrites = newValue } }
    }

    func read(_ key: StoreKey) throws -> Data? { lock.withLock { items[key.rawValue] } }
    func write(_ data: Data, for key: StoreKey) throws {
        try lock.withLock {
            if key == .laundryCheckout, _failCheckoutWrites { throw StoreFailure.write }
            items[key.rawValue] = data
        }
    }
    func delete(_ key: StoreKey) throws {
        try lock.withLock {
            if key == .laundryCheckout, _failCheckoutWrites { throw StoreFailure.write }
            _ = items.removeValue(forKey: key.rawValue)
        }
    }
    enum StoreFailure: Error { case write }
}

/// A clock the poller's ticks move one second each; after `ticks` the task's wait throws.
private final class TickClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    private var left: Int

    init(start: Date, ticks: Int) { _now = start; left = ticks }

    var now: Date { lock.withLock { _now } }

    var tick: @Sendable () async throws -> Void {
        { [self] in
            let done = lock.withLock { () -> Bool in
                left -= 1
                _now = _now.addingTimeInterval(1)
                return left < 0
            }
            if done { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

/// Waits (the main run loop and its tasks going on) until `done` or `seconds`.
@MainActor private func waitFor(seconds: Double = 3, _ done: () -> Bool) async {
    let end = Date().addingTimeInterval(seconds)
    while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
}
