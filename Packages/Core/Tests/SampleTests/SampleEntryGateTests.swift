import XCTest
import Core
import CoreTestSupport

/// The platform as the hot-water engine sees it: authorizes and settles at once.
private struct InstantGateway: ShowerGateway {
    let authorization: ShowerAuthorization
    var isAvailable: Bool { true }
    func authorize(_ binding: ShowerBinding, frame: Data) async throws -> ShowerAuthorization { authorization }
    func settle(_ binding: ShowerBinding, frame: Data) async throws -> ShowerReceipt { ShowerReceipt(amount: Money(fen: 100)) }
}

/// The platform with its settle held until the test lets it go (`release`); `reached` fires
/// when the settle request arrives, `settles` counts them.
private final class HeldSettleGateway: ShowerGateway, @unchecked Sendable {
    let held: AsyncStream<Void>
    let reached = Signal()
    private let lock = NSLock()
    private var _settles = 0
    var settles: Int { lock.withLock { _settles } }
    init(held: AsyncStream<Void>) { self.held = held }
    var isAvailable: Bool { true }
    func authorize(_ binding: ShowerBinding, frame: Data) async throws -> ShowerAuthorization { throw ServiceError.offline }
    func settle(_ binding: ShowerBinding, frame: Data) async throws -> ShowerReceipt {
        lock.withLock { _settles += 1 }
        reached.fire()
        for await _ in held { break }
        return ShowerReceipt(amount: Money(fen: 100))
    }
}

/// The live hot-water model as the app runs it (`ShowerModel`): a start claims the gate before
/// anything else, mirrors the record the engine returns, then gives the claim back. The gate
/// reads the record from this mirror.
@MainActor private final class LiveShower {
    let gate: LiveShowerGate
    let engine: ShowerEngine
    let binding: ShowerBinding
    private(set) var state: ShowerState
    private(set) var startsRefused = 0

    init(gate: LiveShowerGate, engine: ShowerEngine, binding: ShowerBinding) async {
        self.gate = gate; self.engine = engine; self.binding = binding
        state = await engine.state
        gate.record = { [unowned self] in .known(self.state) }
    }

    /// 再结算一次 as `ShowerModel` runs it (first tap, then the confirmation), under one claim:
    /// true when it ran, false when the gate refused it.
    func retrySettle() async -> Bool {
        guard gate.claimLiveStep() else { return false }
        _ = try? await engine.requestSettleRetry()
        _ = try? await engine.confirmSettleRetry(binding)
        state = await engine.state
        gate.liveStepEnded()
        return true
    }

    /// True when the start ran (whatever it ended in), false when the gate refused it.
    func start() async -> Bool {
        guard gate.claimLiveStep() else { startsRefused += 1; return false }
        _ = try? await engine.start(binding)
        state = await engine.state
        gate.liveStepEnded()
        return true
    }
}

/// Signals once, from any thread: a step the test waits for (the start reached the controller).
private final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?
    func fire() {
        let go = lock.withLock { () -> CheckedContinuation<Void, Never>? in fired = true; defer { waiter = nil }; return waiter }
        go?.resume()
    }
    func wait() async {
        await withCheckedContinuation { (go: CheckedContinuation<Void, Never>) in
            let now = lock.withLock { () -> Bool in
                if fired { return true }
                waiter = go; return false
            }
            if now { go.resume() }
        }
    }
}

/// 「先看看示例」 opens only over a real shower record known to be at rest, and a real start
/// never begins while it is shown or opening (`LiveShowerGate`).
@MainActor
final class SampleEntryGateTests: XCTestCase {
    let binding = ShowerBinding(studentId: "S-1", schoolId: "1", machineId: "11223344", roomId: "R-1", roomLabel: "99栋 991")
    let authorization = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")

    private func sample(over record: LiveShowerGate.Record) -> (SampleMode, LiveShowerGate) {
        let gate = LiveShowerGate(record: { record })
        return (SampleMode(gate: gate), gate)
    }

    private static let underWay: [(String, ShowerState)] = [
        ("authorizing", ShowerState(phase: .authorizing, machineID: "11223344", authorizeSent: true)),
        ("writePending", ShowerState(phase: .writePending, machineID: "11223344", startedAt: Date(), authorizationID: "A1")),
        ("running", ShowerState(phase: .running, machineID: "11223344", startedAt: Date(), authorizationID: "A1")),
        ("closing", ShowerState(phase: .closing, machineID: "11223344", startedAt: Date(), authorizationID: "A1", closeSent: true)),
        ("settling", ShowerState(phase: .settling, machineID: "11223344", startedAt: Date(), authorizationID: "A1", consumption: "AA")),
        ("running, to check", ShowerState(phase: .running, machineID: "11223344", startedAt: Date(), stateReviewRequired: true)),
    ]

    /// Every state of a shower still under way (connecting, water on or maybe on, closing,
    /// settling) refuses the sample; nothing opens and nothing is chosen. A running record whose
    /// controller said not in use is still a running record: it refuses too.
    func testEveryShowerNotYetEndedRefusesTheSample() {
        for (name, state) in Self.underWay {
            let (sample, gate) = sample(over: .known(state))
            XCTAssertFalse(gate.sampleAllowed, name)
            XCTAssertEqual(sample.enter(), .refused, name)
            XCTAssertFalse(sample.isActive, name)
            XCTAssertNil(sample.services, name)
            XCTAssertTrue(gate.claimLiveStep(), "a refused sample still holds off a start (\(name))")
        }
    }

    /// A record not read yet, or one that could not be read, refuses too: nothing says the
    /// shower is over.
    func testARecordNotKnownRefusesTheSample() {
        for record in [LiveShowerGate.Record.notLoaded, .unreadable] {
            let (sample, gate) = sample(over: record)
            XCTAssertFalse(gate.sampleAllowed)
            XCTAssertEqual(sample.enter(), .refused)
            XCTAssertFalse(sample.isActive)
        }
        // The default before the live model is up: nothing known.
        let sample = SampleMode(gate: LiveShowerGate())
        XCTAssertEqual(sample.enter(), .refused)
    }

    /// A shower over but awaiting review (待核对): its close or its settlement not confirmed.
    static let awaitingReview = ShowerState(phase: .failed, machineID: "11223344", startedAt: Date(), authorizationID: "A1",
                                            consumption: "AA",
                                            failure: ShowerFailure(reason: .settleUnconfirmed, needsReview: true))

    /// At rest (nothing yet, a settled shower, a failure that issued nothing, a shower awaiting
    /// review) the sample opens.
    func testARecordAtRestLetsTheSampleOpen() {
        let rest = [ShowerState.idle,
                    ShowerState(phase: .done, machineID: "11223344", startedAt: Date(), endedAt: Date()),
                    ShowerState(phase: .failed, machineID: "11223344", failure: ShowerFailure(reason: .deviceUnavailable, needsReview: false)),
                    Self.awaitingReview,
                    ShowerState(phase: .failed, machineID: "11223344", startedAt: Date(),
                                failure: ShowerFailure(reason: .closeUnconfirmed, needsReview: true))]
        for state in rest {
            let (sample, gate) = sample(over: .known(state))
            XCTAssertTrue(gate.sampleAllowed)
            XCTAssertEqual(sample.enter(), .entered)
            XCTAssertTrue(sample.isActive)
            sample.leave()
            XCTAssertTrue(gate.sampleAllowed)
        }
    }

    /// Inside the sample no real start begins; after it, one may again.
    func testNoRealStartWhileTheSampleIsShown() {
        let (sample, gate) = sample(over: .known(.idle))
        XCTAssertEqual(sample.enter(), .entered)
        XCTAssertFalse(gate.claimLiveStep())
        XCTAssertEqual(gate.liveStepsUnderWay, 0)
        sample.leave()
        XCTAssertTrue(gate.claimLiveStep())
        gate.liveStepEnded()
        // The other ways out give it back too.
        // A login link waits for the sample: still no start.
        XCTAssertEqual(sample.enter(), .entered)
        XCTAssertEqual(sample.open(URL(string: "campusdaily://login")!), .held)
        XCTAssertFalse(gate.claimLiveStep())
        sample.leave()
        XCTAssertTrue(gate.claimLiveStep())
        gate.liveStepEnded()
        XCTAssertEqual(sample.enter(), .entered)
        sample.leaveForLive()
        XCTAssertTrue(gate.claimLiveStep())
    }

    /// Over a shower awaiting review the sample opens, but no real start begins while it is
    /// shown, and 再结算一次 is out of its reach: the sample's services hold no record, so their
    /// engine has nothing to settle again.
    func testAShowerAwaitingReviewOpensTheSampleButNothingRealRuns() async throws {
        XCTAssertTrue(Self.awaitingReview.canRetrySettle, "the live record could be settled again")
        let (sample, gate) = sample(over: .known(Self.awaitingReview))
        XCTAssertEqual(sample.enter(), .entered)
        XCTAssertFalse(gate.claimLiveStep())
        XCTAssertEqual(gate.liveStepsUnderWay, 0)
        let services = try XCTUnwrap(sample.services)
        XCTAssertNil(try services.showerVault.showerState())
        let engine = try services.showerEngine(gateway: InstantGateway(authorization: authorization), bleName: "fixture-ble")
        let state = await engine.state
        XCTAssertFalse(state.canRetrySettle)
        do {
            _ = try await engine.requestSettleRetry()
            XCTFail("nothing to settle again in the sample")
        } catch {}
        sample.leave()
        XCTAssertTrue(gate.claimLiveStep())
    }

    /// 再结算一次 on a shower awaiting review and 「先看看示例」 asked for at once, in either order:
    /// exactly one goes through. A settle in flight (held at the platform) keeps the sample shut
    /// until its record is back; a sample shown refuses the retry before anything is sent.
    func testRetrySettleAndEnteringAtOnceLetOnlyOneThrough() async throws {
        for retryFirst in [true, false] {
            let store = InMemorySecureStore()
            try StoredShowerVault(store: store).saveShowerState(Self.awaitingReview)
            let (held, release) = AsyncStream<Void>.makeStream()
            let gateway = HeldSettleGateway(held: held)
            let engine = try ShowerEngine(transport: FakeShowerTransport(), gateway: gateway,
                                          vault: StoredShowerVault(store: store), configuration: .init(bleName: "fixture-ble"))
            let gate = LiveShowerGate()
            let live = await LiveShower(gate: gate, engine: engine, binding: binding)
            XCTAssertTrue(live.state.canRetrySettle, "the record can be settled again (retry first: \(retryFirst))")
            let sample = SampleMode(gate: gate)

            let entry: SampleEntry
            let retry: Task<Bool, Never>
            if retryFirst {
                retry = Task { await live.retrySettle() }
                await gateway.reached.wait()   // the settle is at the platform
                entry = sample.enter()
            } else {
                entry = sample.enter()
                retry = Task { await live.retrySettle() }
                _ = await retry.value
            }
            release.yield(); release.finish()
            let retried = await retry.value

            XCTAssertNotEqual(retried, entry == .entered, "exactly one wins (retry first: \(retryFirst))")
            if retryFirst {
                XCTAssertEqual(gateway.settles, 1)
                XCTAssertFalse(sample.isActive)
                XCTAssertEqual(sample.enter(), .entered, "the retry is over: the sample may open now")
            } else {
                XCTAssertEqual(gateway.settles, 0, "nothing sent while the sample is shown")
                XCTAssertTrue(live.state.canRetrySettle, "the record still waits for its retry")
                XCTAssertTrue(sample.isActive)
            }
        }
    }

    /// No link opens the sample: the login and widget links reach the live app (the login step,
    /// whose entry is the gated one), and the entry after them is still refused while a shower
    /// is under way.
    func testLinksNeverOpenTheSampleOverAShowerUnderWay() {
        let running = ShowerState(phase: .running, machineID: "11223344", startedAt: Date(), authorizationID: "A1")
        let (sample, _) = sample(over: .known(running))
        for text in ["campusdaily://login", "campusdaily://settings/account", "campusdaily://home", "campusdaily://settings"] {
            XCTAssertEqual(sample.open(URL(string: text)!), .live, text)
            XCTAssertFalse(sample.isActive, text)
            XCTAssertEqual(sample.enter(), .refused, text)
            _ = sample.takePendingLink()
        }
    }

    /// A real start is under way (its claim taken, the engine connecting) when 「先看看示例」 is
    /// tapped: the sample is refused, and the start goes on to running. The interleaving is
    /// fixed by the fake controller, which answers only when the test lets it.
    func testTheSampleIsRefusedWhileARealStartIsUnderWay() async throws {
        let transport = FakeShowerTransport()
        let (probeHeld, release) = AsyncStream<Void>.makeStream()
        let reached = Signal()
        transport.onExchange = { _ in reached.fire() }
        transport.script(.after(probeHeld, FakeFrames.identity("11223344")), .frame(FakeFrames.ack))
        let engine = try ShowerEngine(transport: transport, gateway: InstantGateway(authorization: authorization),
                                      vault: StoredShowerVault(store: InMemorySecureStore()), configuration: .init(bleName: "fixture-ble"))
        let gate = LiveShowerGate()
        let live = await LiveShower(gate: gate, engine: engine, binding: binding)
        let sample = SampleMode(gate: gate)

        let start = Task { await live.start() }
        await reached.wait()  // the start is at the controller; its record says authorizing or still idle
        XCTAssertEqual(sample.enter(), .refused)
        XCTAssertFalse(sample.isActive)
        release.yield(); release.finish()
        let started = await start.value
        XCTAssertTrue(started)
        XCTAssertEqual(live.state.phase, .running)
        XCTAssertEqual(sample.enter(), .refused, "the water is on now")
        XCTAssertFalse(sample.isActive)
    }

    /// The sample is shown when a real start is asked for (Siri, the page): it is refused before
    /// anything reaches the controller, and the record stays at rest.
    func testARealStartIsRefusedOnceTheSampleIsShown() async throws {
        let transport = FakeShowerTransport()
        let engine = try ShowerEngine(transport: transport, gateway: InstantGateway(authorization: authorization),
                                      vault: StoredShowerVault(store: InMemorySecureStore()), configuration: .init(bleName: "fixture-ble"))
        let gate = LiveShowerGate()
        let live = await LiveShower(gate: gate, engine: engine, binding: binding)
        let sample = SampleMode(gate: gate)
        XCTAssertEqual(sample.enter(), .entered)
        let started = await live.start()
        XCTAssertFalse(started)
        XCTAssertEqual(transport.connects, [])
        XCTAssertEqual(transport.writes, [])
        XCTAssertEqual(live.state.phase, .idle)
        XCTAssertTrue(sample.isActive)
    }

    /// Both asked for at once, in either order of arrival: exactly one goes through, and the
    /// sample is never shown over a real shower under way.
    func testEnteringAndStartingAtOnceLetOnlyOneThrough() async throws {
        for startFirst in [true, false] {
            let transport = FakeShowerTransport()
            let (probeHeld, release) = AsyncStream<Void>.makeStream()
            let reached = Signal()
            transport.onExchange = { _ in reached.fire() }
            transport.script(.after(probeHeld, FakeFrames.identity("11223344")), .frame(FakeFrames.ack))
            let engine = try ShowerEngine(transport: transport, gateway: InstantGateway(authorization: authorization),
                                          vault: StoredShowerVault(store: InMemorySecureStore()), configuration: .init(bleName: "fixture-ble"))
            let gate = LiveShowerGate()
            let live = await LiveShower(gate: gate, engine: engine, binding: binding)
            let sample = SampleMode(gate: gate)

            // `startFirst` picks which of the two the main actor takes first; the other comes
            // while the first is under way (the start held at the controller, or the sample shown).
            let entry: SampleEntry
            let startTask: Task<Bool, Never>
            if startFirst {
                startTask = Task { await live.start() }
                await reached.wait()
                entry = sample.enter()
            } else {
                entry = sample.enter()
                startTask = Task { await live.start() }
                _ = await startTask.value
            }
            release.yield(); release.finish()
            let started = await startTask.value

            XCTAssertNotEqual(started, entry == .entered, "exactly one wins (start first: \(startFirst))")
            let underWay = !LiveShowerGate.allowsSample(.known(live.state))
            XCTAssertFalse(sample.isActive && underWay, "the sample is shown over a real shower (start first: \(startFirst))")
            if startFirst { XCTAssertEqual(live.state.phase, .running) } else { XCTAssertEqual(transport.connects, []) }
        }
    }
}
