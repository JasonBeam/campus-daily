import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// Scripted gateway: results are consumed in order; `.hang` waits for cancellation.
final class FakeGateway: ShowerGateway, @unchecked Sendable {
    // @unchecked: state guarded by `lock`.
    enum Outcome<T: Sendable>: Sendable { case ok(T), fail(ServiceError), hang }
    private let lock = NSLock()
    private var authorizeResults: [Outcome<ShowerAuthorization>] = []
    private var settleResults: [Outcome<ShowerReceipt>] = []
    private var _authorizeFrames: [Data] = []
    private var _settleFrames: [Data] = []

    func scriptAuthorize(_ o: Outcome<ShowerAuthorization>...) { lock.withLock { authorizeResults += o } }
    func scriptSettle(_ o: Outcome<ShowerReceipt>...) { lock.withLock { settleResults += o } }
    var authorizeFrames: [Data] { lock.withLock { _authorizeFrames } }
    var settleFrames: [Data] { lock.withLock { _settleFrames } }

    func authorize(_ binding: ShowerBinding, frame: Data) async throws -> ShowerAuthorization {
        let o: Outcome<ShowerAuthorization> = lock.withLock {
            _authorizeFrames.append(frame)
            return authorizeResults.isEmpty ? .fail(.timedOut) : authorizeResults.removeFirst()
        }
        return try await Self.resolve(o)
    }

    func settle(_ binding: ShowerBinding, frame: Data) async throws -> ShowerReceipt {
        let o: Outcome<ShowerReceipt> = lock.withLock {
            _settleFrames.append(frame)
            return settleResults.isEmpty ? .fail(.timedOut) : settleResults.removeFirst()
        }
        return try await Self.resolve(o)
    }

    static func resolve<T: Sendable>(_ o: Outcome<T>) async throws -> T {
        switch o {
        case .ok(let v): return v
        case .fail(let e): throw e
        case .hang:
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
            throw CancellationError()
        }
    }
}

/// Vault whose session writes fail once `failWhen` matches the state being written.
final class FlakyVault: ShowerVault, @unchecked Sendable {
    let inner: StoredShowerVault
    let failWhen: @Sendable (ShowerState?) -> Bool
    init(inner: StoredShowerVault, failWhen: @escaping @Sendable (ShowerState?) -> Bool) { self.inner = inner; self.failWhen = failWhen }
    func binding() throws -> ShowerBinding? { try inner.binding() }
    func saveBinding(_ binding: ShowerBinding?) throws { try inner.saveBinding(binding) }
    func showerState() throws -> ShowerState? { try inner.showerState() }
    func saveShowerState(_ state: ShowerState?) throws {
        if failWhen(state) { throw StorageError(operation: "write water.session", status: -1) }
        try inner.saveShowerState(state)
    }
}

final class RecordingHooks: ShowerHooks, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    var events: [String] { lock.withLock { _events } }
    func scheduleUnsettledReminder(after seconds: TimeInterval) async { lock.withLock { _events.append("schedule:\(Int(seconds))") } }
    func cancelUnsettledReminder() async { lock.withLock { _events.append("cancel") } }
    func diagnostic(_ event: String) async { lock.withLock { _events.append(event) } }
}

/// Holds a task so a fake can cancel it mid-flow.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    func set(_ t: Task<Void, Never>) { lock.withLock { task = t } }
    func cancel() { lock.withLock { task?.cancel() } }
}

final class ShowerEngineTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let close = Data([0xAC, 0x55, 0x44, 0x77, 0xAA])
    let receipt = ShowerReceipt(amount: Money(fen: 163))
    var identity: Data { FakeFrames.identity(machine) }
    var consumption: Data { FakeFrames.identity(machine, tail: 9) }

    var store: InMemorySecureStore!
    var vault: StoredShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!
    var hooks: RecordingHooks!

    override func setUp() {
        store = InMemorySecureStore()
        vault = StoredShowerVault(store: store)
        transport = FakeShowerTransport()
        gateway = FakeGateway()
        hooks = RecordingHooks()
    }

    func engine(_ v: ShowerVault? = nil) throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: v ?? vault,
                         configuration: .init(bleName: "fixture-ble", reminderMinutes: 30), hooks: hooks,
                         now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    /// A fresh engine over the same vault (relaunch) and its restored state.
    func restored() async throws -> ShowerState { try await engine().state }

    func expect(_ expected: ShowerEngineError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let e as ShowerEngineError { XCTAssertEqual(e, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    func startRunning(_ e: ShowerEngine) async throws {
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding)
        XCTAssertEqual(s.phase, .running)
    }

    // MARK: Happy path

    func testHappyPathWritesExactlyProbeAuthorizationProbeClose() async throws {
        try vault.saveBinding(binding)
        let e = try engine()
        try await startRunning(e)
        XCTAssertEqual(gateway.authorizeFrames, [identity])
        XCTAssertEqual(try vault.showerState()?.phase, .running, "persisted")
        XCTAssertEqual(try vault.binding()?.peripheralID, "PERIPHERAL-A", "verified peripheral remembered")

        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(done.receipt, receipt)
        let title = await e.display.title
        XCTAssertEqual(title, "本次 ¥1.63")
        XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand, auth.payload, ShowerFrames.probeCommand, close])
        XCTAssertEqual(transport.connects.last, FakeShowerTransport.Connect(required: "PERIPHERAL-A", preferred: nil),
                       "finish talks to the session's controller only")
        XCTAssertEqual(gateway.settleFrames, [consumption])
        XCTAssertEqual(hooks.events, ["schedule:1800", "cancel"])
        XCTAssertEqual(try vault.showerState()?.phase, .done)

        let idle = try await e.dismiss()
        XCTAssertEqual(idle.phase, .idle)
        XCTAssertEqual(idle.lastReceipt, receipt)
    }

    /// A dismiss for a record that has since been replaced (a new start ran) clears nothing.
    func testDismissOnlyClearsTheRecordItWasAskedFor() async throws {
        let e = try engine()
        try await startRunning(e)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        var earlier = done
        earlier.startedAt = done.startedAt?.addingTimeInterval(-600)
        let kept = try await e.dismiss(only: earlier)
        XCTAssertEqual(kept, done)
        XCTAssertEqual(try vault.showerState()?.phase, .done)
        let idle = try await e.dismiss(only: done)
        XCTAssertEqual(idle.phase, .idle)
    }

    func testUpdatesStreamPublishesEveryPhase() async throws {
        let e = try engine()
        let stream = await e.updates()
        try await startRunning(e)
        var phases: [ShowerPhase] = []
        for await s in stream {
            phases.append(s.phase)
            if s.phase == .running { break }
        }
        XCTAssertEqual(phases, [.idle, .authorizing, .authorizing, .writePending, .running])
    }

    // MARK: Cancel while connecting

    func waitUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<400 where !(await condition()) { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// 取消 during the Bluetooth connect: the task is cut short, nothing reaches the platform and
    /// no record is left.
    func testACancelDuringTheConnectSendsNothing() async throws {
        let e = try engine()
        transport.script(.hang)
        let b = binding
        let task = Task { try? await e.start(b) }
        await waitUntil { [transport] in transport!.writes.count == 1 }
        let accepted = await e.cancelStart()
        XCTAssertTrue(accepted)
        task.cancel()
        _ = await task.value
        let s = await e.state
        XCTAssertEqual(s.phase, .failed)
        XCTAssertEqual(s.failure?.needsReview, false)
        XCTAssertTrue(gateway.authorizeFrames.isEmpty)
        XCTAssertEqual(try vault.showerState()?.phase ?? .idle, .idle, "no record left")
        XCTAssertTrue(s.canStart)
    }

    /// 取消 accepted after the controller answered but before the authorize request: the request
    /// never leaves, even with the task left running.
    func testAnAcceptedCancelKeepsTheAuthorizeRequestBack() async throws {
        let e = try engine()
        let (gate, open) = AsyncStream.makeStream(of: Void.self)
        transport.script(.after(gate, identity))
        let b = binding
        let task = Task { try? await e.start(b) }
        await waitUntil { [transport] in transport!.writes.count == 1 }
        let accepted = await e.cancelStart()
        XCTAssertTrue(accepted)
        open.yield(); open.finish()
        _ = await task.value
        let s = await e.state
        XCTAssertEqual(s.failure?.reason, .deviceUnavailable)
        XCTAssertEqual(s.failure?.needsReview, false)
        XCTAssertTrue(gateway.authorizeFrames.isEmpty)
    }

    /// Once the authorize request has left, a cancel is refused: the start goes on, and after
    /// it has finished there is nothing to cancel either.
    func testACancelAfterTheAuthorizeRequestLeftIsRefused() async throws {
        let e = try engine()
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.hang)
        let b = binding
        let task = Task { try? await e.start(b) }
        await waitUntil { [gateway] in gateway!.authorizeFrames.count == 1 }
        let accepted = await e.cancelStart()
        XCTAssertFalse(accepted)
        task.cancel()
        _ = await task.value
        let refusedWhenIdle = await e.cancelStart()
        XCTAssertFalse(refusedWhenIdle)
    }

    // MARK: Refusal / uncertainty

    /// While a reset runs, a start (the in-app button and the 开始洗澡 shortcut both come here)
    /// is refused before anything reaches the controller; once the marker is stale it goes ahead.
    func testAStartIsRefusedWhileAResetRuns() async throws {
        let marker = ResetMarker(store: InMemorySecureStore())
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try marker.begin(at: t)
        let e = try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                                 configuration: .init(bleName: "fixture-ble", reminderMinutes: 30), hooks: hooks,
                                 resetMarker: marker, now: { t })
        do { _ = try await e.start(binding); XCTFail("expected the refusal") }
        catch { XCTAssertEqual(error as? AppReset.InProgress, AppReset.InProgress()); XCTAssertEqual(error.localizedDescription, "正在重置") }
        XCTAssertTrue(transport.writes.isEmpty, "nothing sent")
        XCTAssertNil(try vault.showerState(), "nothing recorded")

        let stale = try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                                     configuration: .init(bleName: "fixture-ble", reminderMinutes: 30), hooks: hooks,
                                     resetMarker: marker, now: { t.addingTimeInterval(ResetMarker.staleAfter + 1) })
        try await startRunning(stale)
    }

    func testRefusalLeavesNoRecordAndAllowsAnotherStart() async throws {
        let e = try engine()
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.fail(.rejected(.lxt6, code: "1", message: "余额不足")))
        let s = try await e.start(binding)
        XCTAssertEqual(s.failure?.reason, .authorizeRefused)
        let title = await e.display.title
        XCTAssertEqual(title, "余额不足")
        XCTAssertEqual(try vault.showerState()?.phase, .idle)
        XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand], "nothing written to the controller")
        try await startRunning(e)
    }

    func testUncertainAuthorizeBlocksUntilResolvedManually() async throws {
        let e = try engine()
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.fail(.timedOut))
        let s = try await e.start(binding)
        XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
        XCTAssertEqual(s.failure?.needsReview, true)
        await expect(.blocked) { try await e.start(self.binding) }
        XCTAssertEqual(gateway.authorizeFrames.count, 1)

        // Survives relaunch.
        let relaunched = try engine()
        let restored = await relaunched.state
        XCTAssertEqual(restored.failure?.reason, .authorizeUncertain)
        await expect(.blocked) { try await relaunched.start(self.binding) }

        let idle = try await relaunched.resolveManually()
        XCTAssertEqual(idle.phase, .idle)
        XCTAssertTrue(hooks.events.contains("resolvedManually.failed"))
        try await startRunning(relaunched)
    }

    func testWrongControllerIsRejectedBeforeAuthorize() async throws {
        let e = try engine()
        transport.script(.frame(FakeFrames.identity("99999999")))
        let s = try await e.start(binding)
        XCTAssertEqual(s.failure?.reason, .wrongDevice)
        XCTAssertTrue(gateway.authorizeFrames.isEmpty)
        XCTAssertEqual(transport.disconnects, 1)
    }

    // MARK: writePending

    func testUnconfirmedWriteShowsRunningAndFinishCloses() async throws {
        let e = try engine()
        transport.script(.frame(identity), .fail(.timedOut))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding)
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertEqual(s.notice, .device(.timedOut))
        let d = await e.display
        XCTAssertEqual(d.phase, .running)
        XCTAssertTrue(d.writeUnconfirmed)

        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(transport.writes.last, close)
    }

    func testFinishFromWritePendingWhenAuthorizationNeverAppliedDoesNotSettle() async throws {
        let e = try engine()
        transport.script(.frame(identity), .frame(Data([0xAA, 0])))
        gateway.scriptAuthorize(.ok(auth))
        let started = try await e.start(binding)
        XCTAssertEqual(started.notice, .writeUnconfirmed)
        transport.script(.frame(identity))
        let s = try await e.finish(binding)
        XCTAssertEqual(s.phase, .idle)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertFalse(transport.writes.contains(close))
        XCTAssertTrue(hooks.events.contains("finish.writeNeverApplied"))
    }

    func testFinishWithControllerUnreachableKeepsSession() async throws {
        let e = try engine()
        try await startRunning(e)
        transport.scriptConnect(.failure(.notFound))
        let s = try await e.finish(binding)
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(s.notice, .device(.notFound))
        XCTAssertFalse(transport.writes.contains(close))
    }

    // MARK: Settle

    func testSettleFailureIsNotRetriedAndManualRetryNeedsTwoSteps() async throws {
        let e = try engine()
        try await startRunning(e)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.fail(.timedOut))
        let f = try await e.finish(binding)
        XCTAssertEqual(f.failure?.reason, .settleUncertain)
        XCTAssertEqual(gateway.settleFrames.count, 1, "never a second automatic settle")
        await expect(.blocked) { try await e.start(self.binding) }
        await expect(.notAllowed) { try await e.confirmSettleRetry(self.binding) }

        let armed = try await e.requestSettleRetry()
        XCTAssertTrue(armed.settleRetryArmed)
        XCTAssertEqual(gateway.settleFrames.count, 1)
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.confirmSettleRetry(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(done.manualSettleAttempts, 1)
        XCTAssertEqual(gateway.settleFrames, [consumption, consumption])
        XCTAssertTrue(hooks.events.contains("settle.manualRetry#1"))
    }

    func testSettleCancelledMidRequestIsUncertain() async throws {
        let e = try engine()
        try await startRunning(e)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.hang)
        let b = binding
        let task = Task { try await e.finish(b) }
        while gateway.settleFrames.isEmpty { try await Task.sleep(nanoseconds: 2_000_000) }
        await expect(.busy) { try await e.dismiss() }
        task.cancel()
        let s = try await task.value
        XCTAssertEqual(s.failure?.reason, .settleUncertain)
        XCTAssertEqual(s.failure?.needsReview, true)
    }

    // MARK: Relaunch

    func testRelaunchRestoresEachPersistedPhase() async throws {
        let running = ShowerState(phase: .running, machineID: machine, peripheralID: "P", authorizeSent: true, authorizationID: "001122FF")
        try vault.saveShowerState(running)
        do { let r = try await restored(); XCTAssertEqual(r, running) }

        var settling = running
        settling.phase = .settling
        settling.consumption = HexCoding.upper(consumption)
        try vault.saveShowerState(settling)
        let e = try engine()
        let restoredState = await e.state
        XCTAssertEqual(restoredState.failure?.reason, .settleUnconfirmed)
        XCTAssertEqual(try vault.showerState()?.failure?.reason, .settleUnconfirmed, "restored state persisted")
        XCTAssertTrue(gateway.settleFrames.isEmpty, "nothing re-sent on launch")
        _ = try await e.requestSettleRetry()
        gateway.scriptSettle(.ok(receipt))
        let settled = try await e.confirmSettleRetry(binding)
        XCTAssertEqual(settled.phase, .done)

        var closing = running
        closing.phase = .closing
        closing.closingFrom = .running
        closing.closeSent = true
        try vault.saveShowerState(closing)
        do { let r = try await restored(); XCTAssertEqual(r.failure?.reason, .closeUnconfirmed) }

        closing.closeSent = false
        try vault.saveShowerState(closing)
        do { let r = try await restored(); XCTAssertEqual(r.phase, .running) }

        var authorizing = ShowerState(phase: .authorizing, machineID: machine)
        try vault.saveShowerState(authorizing)
        do { let r = try await restored(); XCTAssertEqual(r.phase, .idle) }
        authorizing.authorizeSent = true
        try vault.saveShowerState(authorizing)
        do { let r = try await restored(); XCTAssertEqual(r.failure?.reason, .authorizeUncertain) }
    }

    func testRelaunchedRunningSessionFinishesOnItsPeripheral() async throws {
        try vault.saveShowerState(ShowerState(phase: .running, machineID: machine, peripheralID: "PERIPHERAL-B",
                                              authorizeSent: true, authorizationID: "001122FF"))
        let e = try engine()
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let finished = try await e.finish(binding)
        XCTAssertEqual(finished.phase, .done)
        XCTAssertEqual(transport.connects, [FakeShowerTransport.Connect(required: "PERIPHERAL-B", preferred: nil)])
        let other = ShowerBinding(studentId: "S1", schoolId: "20021", machineId: "99999999", roomId: "R", roomLabel: "x")
        try vault.saveShowerState(ShowerState(phase: .running, machineID: machine, peripheralID: "P", authorizationID: "001122FF"))
        await expect(.wrongBinding) { try await self.engine().finish(other) }
    }

    // MARK: Storage

    func testStorageFailureBeforeAuthorizeSendsNothing() async throws {
        let flaky = FlakyVault(inner: vault, failWhen: { $0?.authorizeSent == true })
        let e = try engine(flaky)
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.ok(auth))
        await expect(.storage) { try await e.start(self.binding) }
        XCTAssertTrue(gateway.authorizeFrames.isEmpty, "authorize never leaves without a stored 'sent' record")
        XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand])
        let blocked = await e.storageBlocked
        XCTAssertTrue(blocked)
        await expect(.storage) { try await e.start(self.binding) }
    }

    func testStorageFailureOnFirstWriteTouchesNothing() async throws {
        store.failWrites(to: .showerSession)
        let e = try engine()
        await expect(.storage) { try await e.start(self.binding) }
        XCTAssertTrue(transport.connects.isEmpty)
        XCTAssertTrue(transport.writes.isEmpty)
    }

    func testStorageFailureBeforeCloseKeepsCloseUnsent() async throws {
        let flaky = FlakyVault(inner: vault, failWhen: { $0?.closeSent == true })
        let e = try engine(flaky)
        try await startRunning(e)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        await expect(.storage) { try await e.finish(self.binding) }
        XCTAssertFalse(transport.writes.contains(close))
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    // MARK: Cancellation

    func testCancelBeforeAuthorizeLeavesIsNotUncertain() async throws {
        let e = try engine()
        let box = TaskBox()
        transport.onExchange = { if $0 == ShowerFrames.probeCommand { box.cancel() } }
        transport.script(.frame(identity))
        let (gate, open) = AsyncStream.makeStream(of: Void.self)
        let b = binding
        let task = Task<Void, Never> {
            for await _ in gate { break }
            _ = try? await e.start(b)
        }
        box.set(task)
        open.yield(); open.finish()
        await task.value
        let s = await e.state
        XCTAssertEqual(s.failure?.reason, .deviceUnavailable)
        XCTAssertEqual(s.failure?.deviceError, .interrupted)
        XCTAssertTrue(gateway.authorizeFrames.isEmpty)
        XCTAssertTrue(s.canStart)
    }

    func testCancelDuringAuthorizeRequestIsUncertain() async throws {
        let e = try engine()
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.hang)
        let b = binding
        let task = Task { try await e.start(b) }
        while gateway.authorizeFrames.isEmpty { try await Task.sleep(nanoseconds: 2_000_000) }
        task.cancel()
        let s = try await task.value
        XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
        XCTAssertFalse(s.canStart)
    }

    func testCancelWhileProbingBeforeAuthorizeFailsCleanly() async throws {
        let e = try engine()
        transport.script(.hang)
        let b = binding
        let task = Task { try await e.start(b) }
        while transport.writes.isEmpty { try await Task.sleep(nanoseconds: 2_000_000) }
        task.cancel()
        let s = try await task.value
        XCTAssertEqual(s.failure?.reason, .deviceUnavailable)
        XCTAssertEqual(try vault.showerState()?.phase, .idle)
    }

    // MARK: Review

    func testReviewContradictionAllowsManualResolve() async throws {
        let e = try engine()
        try await startRunning(e)
        await expect(.notAllowed) { try await e.resolveManually() }
        transport.script(.frame(identity))
        let s = try await e.review(binding)
        XCTAssertTrue(s.stateReviewRequired)
        XCTAssertEqual(s.notice, .notActive)
        let resolved = try await e.resolveManually()
        XCTAssertEqual(resolved.phase, .idle)
        XCTAssertTrue(hooks.events.contains("cancel"))
    }

    func testTargetSelectionNeverGuesses() async throws {
        XCTAssertEqual(try ShowerTargetSelection.select(["A"], required: nil, preferred: nil), "A")
        XCTAssertEqual(try ShowerTargetSelection.select(["A", "B"], required: nil, preferred: "B"), "B")
        XCTAssertThrowsError(try ShowerTargetSelection.select(["A", "B"], required: nil, preferred: "C")) {
            XCTAssertEqual($0 as? ShowerDeviceError, .ambiguous)
        }
        XCTAssertThrowsError(try ShowerTargetSelection.select(["A"], required: "B", preferred: "A")) {
            XCTAssertEqual($0 as? ShowerDeviceError, .notFound)
        }
        let frames = ["A": FakeFrames.identity("99999999"), "B": FakeFrames.identity("11223344")]
        let found = try await ShowerTargetSelection.identify(["A", "B"], machineID: "11223344") { frames[$0]! }
        XCTAssertEqual(found, "B")
        do {
            _ = try await ShowerTargetSelection.identify(["A"], machineID: "11223344") { frames[$0]! }
            XCTFail("expected ambiguous")
        } catch { XCTAssertEqual(error as? ShowerDeviceError, .ambiguous) }
        do {
            _ = try await ShowerTargetSelection.identify(["A"], machineID: "11223344") { _ in throw ShowerDeviceError.busy }
            XCTFail("expected notFound")
        } catch { XCTAssertEqual(error as? ShowerDeviceError, .notFound) }
    }
}
