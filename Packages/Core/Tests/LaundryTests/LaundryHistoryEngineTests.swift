import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// The engine files a finished order only after the checkout record that ends it is saved, and
/// a failed history write never blocks the order flow.
final class LaundryHistoryEngineTests: XCTestCase {
    var store: InMemorySecureStore!
    var vault: StoredLaundryVault!
    var api: FakeLaundryAPI!

    override func setUp() {
        store = InMemorySecureStore()
        vault = StoredLaundryVault(store: store)
        api = FakeLaundryAPI()
    }

    func engine(vault v: LaundryVault? = nil, history: LaundryHistoryRecording?, log: any DebugLogSink = NoDebugLog()) throws -> LaundryEngine {
        let t = L.t0.addingTimeInterval(10)
        return try LaundryEngine(api: api, vault: v ?? vault, launcher: FakeLauncher(), accountID: "acct-1", history: history,
                                 now: { t }, sleep: { _ in }, debugLog: log)
    }

    func active() throws {
        try vault.saveCheckout(LaundryCheckout(phase: .active, draft: L.draft, createdAt: L.t0, orderID: L.orderID,
                                               order: L.order("40", remain: 60), accountID: "acct-1"))
    }

    func testHistoryWrittenAfterCheckoutCommit() async throws {
        try active()
        let recorder = Recorder { [vault] in try? vault!.checkout() }
        let e = try engine(history: recorder)
        api.orders = [.ok(L.order("50"))]
        _ = try await e.refresh()
        XCTAssertEqual(recorder.recorded.map(\.status.code), ["50"])
        XCTAssertEqual(recorder.seenAtWrite.first??.lastOutcome?.status.code, "50", "the ended record was already saved")
        XCTAssertEqual(recorder.seenAtWrite.first??.phase, LaundryPhase.none)
    }

    func testNoHistoryWhenTheCheckoutSaveFails() async throws {
        try active()
        let recorder = Recorder { nil }
        let flaky = FlakyLaundryVault(inner: vault) { $0?.lastOutcome != nil || $0 == nil }
        let e = try engine(vault: flaky, history: recorder)
        api.orders = [.ok(L.order("50"))]
        do { _ = try await e.refresh(); XCTFail("expected the storage error") }
        catch { XCTAssertEqual(error as? LaundryEngineError, .storage) }
        XCTAssertTrue(recorder.recorded.isEmpty)
    }

    func testHistoryFailureDoesNotBlockEngine() async throws {
        try vault.saveCheckout(LaundryCheckout(phase: .created, draft: L.draft, createdAt: L.t0, orderID: L.orderID,
                                               order: L.order("10"), accountID: "acct-1"))
        let recorder = Recorder { nil }
        recorder.fails = true
        let log = RecordingDebugLog()
        let e = try engine(history: recorder, log: log)
        api.orders = [.ok(L.order("53"))]
        let s = try await e.refresh()
        XCTAssertEqual(s.lastOutcome?.status.code, "53")
        let blocked = await e.storageBlocked
        XCTAssertFalse(blocked)
        XCTAssertTrue(log.events.contains(.laundryHistory(.writeFailed)))
        // The next order still goes through.
        api.creates = [.ok("TESTORDER0002")]
        api.orders = [.ok(L.order("10", id: "TESTORDER0002"))]
        let next = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        XCTAssertEqual(next.phase, .created)
    }

    func testRealStoreFilesTheEndedOrder() async throws {
        try active()
        let history = LaundryHistoryStore(store: store, random: { Data(repeating: 3, count: 32) })
        let e = try engine(history: history)
        api.orders = [.ok(L.order("50", price: 380))]
        _ = try await e.refresh()
        let shown = history.entries(accountID: "acct-1", openOrderID: nil, now: L.t0.addingTimeInterval(20))
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.amount, Money(fen: 380))
        XCTAssertEqual(shown.first?.machine, "测试洗衣机01")
    }
}

final class Recorder: LaundryHistoryRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var _recorded: [LaundryFinishedOrder] = []
    private var _seen: [LaundryCheckout?] = []
    private var _fails = false
    private let look: @Sendable () -> LaundryCheckout?
    init(look: @escaping @Sendable () -> LaundryCheckout?) { self.look = look }
    var recorded: [LaundryFinishedOrder] { lock.withLock { _recorded } }
    var seenAtWrite: [LaundryCheckout?] { lock.withLock { _seen } }
    var fails: Bool { get { lock.withLock { _fails } } set { lock.withLock { _fails = newValue } } }
    func record(_ order: LaundryFinishedOrder, now: Date) throws {
        let seen = look()
        try lock.withLock {
            _seen.append(seen)
            if _fails { throw StorageError(operation: "write laundry.history", status: -1) }
            _recorded.append(order)
        }
    }
}
