import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// A clock the fakes move forward, so "connecting took 15 s" happens without waiting.
private final class StepClock: @unchecked Sendable {
    // @unchecked: state guarded by `lock`.
    private let lock = NSLock()
    private var _now: Date
    init(_ start: Date) { _now = start }
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }
}

/// The platform takes `delay` seconds (on the step clock) to answer the authorize request.
private struct SlowGateway: ShowerGateway {
    let inner: FakeGateway
    let clock: StepClock
    let delay: TimeInterval
    func authorize(_ binding: ShowerBinding, frame: Data) async throws -> ShowerAuthorization {
        clock.advance(delay)
        return try await inner.authorize(binding, frame: frame)
    }
    func settle(_ binding: ShowerBinding, frame: Data) async throws -> ShowerReceipt {
        try await inner.settle(binding, frame: frame)
    }
}

/// Records the clock when the engine asks for the 「还没结束洗澡？」 reminder.
private final class ClockedHooks: ShowerHooks, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: StepClock
    private var _scheduled: [(at: Date, after: TimeInterval)] = []
    init(_ clock: StepClock) { self.clock = clock }
    var scheduled: [(at: Date, after: TimeInterval)] { lock.withLock { _scheduled } }
    func scheduleUnsettledReminder(after seconds: TimeInterval) async {
        let at = clock.now
        lock.withLock { _scheduled.append((at, seconds)) }
    }
    func cancelUnsettledReminder() async {}
    func diagnostic(_ event: String) async {}
}

/// The shower timer counts from the moment water may flow (出水), not from the 开始洗澡 tap:
/// connecting and authorizing take ~15 s that are not shower time.
final class ShowerTimerOriginTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheTimerTheLockScreenAndTheReminderAllStartWhenTheWaterDoes() async throws {
        let clock = StepClock(t0)
        let transport = FakeShowerTransport()
        let gateway = FakeGateway()
        let hooks = ClockedHooks(clock)
        let vault = StoredShowerVault(store: InMemorySecureStore())
        let engine = try ShowerEngine(transport: transport, gateway: SlowGateway(inner: gateway, clock: clock, delay: 15),
                                      vault: vault, configuration: .init(bleName: "fixture-ble", reminderMinutes: 30),
                                      hooks: hooks, now: { clock.now })
        transport.script(.frame(FakeFrames.identity(machine)), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))

        let s = try await engine.start(binding)          // tapped at t0, authorized at t0+15
        XCTAssertEqual(s.phase, .running)
        let water = t0.addingTimeInterval(15)
        XCTAssertEqual(s.startedAt, water, "the timer's origin is the water, not the tap")
        XCTAssertEqual(try vault.showerState()?.startedAt, water, "persisted the same way")

        let at20 = t0.addingTimeInterval(20)
        let page = try XCTUnwrap(ShowerPage(s))
        XCTAssertEqual(page.phase, .running)
        XCTAssertEqual(at20.timeIntervalSince(try XCTUnwrap(page.startedAt)), 5, "5 s of water, not 20")

        XCTAssertEqual(ShowerActivityAction(s, now: at20), .show(startedAt: water, writeUnconfirmed: false),
                       "Live Activity / Dynamic Island / lock screen count from the water")
        XCTAssertEqual(AppReset.Resync(shower: s, now: at20).showerReminderStart, water,
                       "the app's reminder is scheduled from the water")
        XCTAssertEqual(hooks.scheduled.map(\.at), [water], "the engine's reminder hook runs when the water starts")
        XCTAssertEqual(hooks.scheduled.map(\.after), [30 * 60])
    }

    /// The write is not acknowledged (shown as running on purpose): the water may still flow,
    /// so the timer is there and counts from the same moment.
    func testAnUnacknowledgedWriteStillCountsFromTheWater() {
        let tapped = ShowerReducer.reduce(.idle, .start(machineID: machine, preferredPeripheral: nil)).0
        XCTAssertNil(tapped.startedAt, "connecting is not shower time")
        var s = ShowerReducer.reduce(tapped, .connected(peripheralID: "P", probe: FakeFrames.identity(machine))).0
        XCTAssertNil(s.startedAt)
        let water = t0.addingTimeInterval(15)
        s = ShowerReducer.reduce(s, .authorized(auth, at: water)).0
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertEqual(s.startedAt, water)
        s = ShowerReducer.reduce(s, .writeReplied(Data([0x00]))).0
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertEqual(s.startedAt, water)
        XCTAssertEqual(ShowerPage(s)?.startedAt, water)
        XCTAssertEqual(ShowerActivityAction(s, now: t0.addingTimeInterval(20)), .show(startedAt: water, writeUnconfirmed: true))
    }

    /// Duration (「上次 11 分钟」, the settled lock screen, the done page) counts from the water too.
    func testTheDurationCountsFromTheWater() {
        let water = t0.addingTimeInterval(15)
        let done = ShowerState(phase: .done, startedAt: water, receipt: ShowerReceipt(amount: Money(fen: 132)),
                               endedAt: water.addingTimeInterval(10 * 60 + 40))
        XCTAssertEqual(done.minutes, 11)
        XCTAssertEqual(ShowerPage(done)?.minutes, 11)
        XCTAssertEqual(ShowerActivityAction(done, now: water), .settled(startedAt: water, minutes: 11, amountYuan: 1.32, dismissAfter: 4))
        XCTAssertNil(ShowerState(phase: .done, endedAt: water).minutes, "no water start, no duration")
    }

    /// A failure before the water never carries a timer origin.
    func testAFailureBeforeTheWaterHasNoTimer() {
        var s = ShowerReducer.reduce(.idle, .start(machineID: machine, preferredPeripheral: nil)).0
        s = ShowerReducer.reduce(s, .connected(peripheralID: "P", probe: FakeFrames.identity(machine))).0
        s = ShowerReducer.reduce(s, .authorizeFailed(.timedOut)).0
        XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
        XCTAssertNil(s.startedAt)
        XCTAssertEqual(ShowerActivityAction(s, now: t0), .end)
    }

    // MARK: Records saved by the previous version (startedAt = the tap)

    /// The JSON the previous version wrote: `startedAt` was the tap time.
    private func oldRecord(_ phase: ShowerPhase, startedAt: Date, extra: String = "") -> Data {
        Data("""
        {"phase":"\(phase.rawValue)","machineID":"11223344","peripheralID":"P","startedAt":\(startedAt.timeIntervalSinceReferenceDate),
         "authorizeSent":true,"authorizationID":"001122FF","closeSent":false,"stateReviewRequired":false,"reviewing":false,
         "settleRetryArmed":false,"manualSettleAttempts":0\(extra)}
        """.utf8)
    }

    private func restoreOld(_ data: Data) throws -> ShowerState {
        let store = InMemorySecureStore()
        try store.write(data, for: .showerSession)
        _ = try ShowerEngine(transport: FakeShowerTransport(), gateway: FakeGateway(), vault: StoredShowerVault(store: store),
                                      configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        let restored = try XCTUnwrap(try StoredShowerVault(store: store).showerState())
        return restored
    }

    /// A shower running when the app was updated keeps its old origin (the tap): the timer, the
    /// lock screen and the reminder stay where they were (no jump back), and it can still end.
    func testAnOldRunningShowerKeepsCountingFromItsSavedStart() throws {
        let tap = t0.addingTimeInterval(-120)
        let s = try restoreOld(oldRecord(.running, startedAt: tap))
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(s.startedAt, tap)
        XCTAssertTrue(s.canFinish)
        XCTAssertEqual(ShowerActivityAction(s, now: t0), .show(startedAt: tap, writeUnconfirmed: false))
        XCTAssertEqual(AppReset.Resync(shower: s, now: t0).showerReminderStart, tap)
    }

    /// An old record stopped before the water (authorize may have been issued) keeps no timer
    /// origin: the tap was never water.
    func testAnOldRecordStoppedBeforeTheWaterDropsItsTapTime() throws {
        let tap = t0.addingTimeInterval(-60)
        let s = try restoreOld(oldRecord(.authorizing, startedAt: tap))
        XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
        XCTAssertNil(s.startedAt)

        let failed = try restoreOld(oldRecord(.failed, startedAt: tap,
                                              extra: #","failure":{"reason":"authorizationInvalid","needsReview":true}"#))
        XCTAssertEqual(failed.failure?.reason, .authorizationInvalid)
        XCTAssertNil(failed.startedAt)
    }

    /// An old record that failed after the water keeps its start (the lock screen's 「不确定」 line).
    func testAnOldRecordThatFailedAfterTheWaterKeepsItsStart() throws {
        let tap = t0.addingTimeInterval(-600)
        let s = try restoreOld(oldRecord(.failed, startedAt: tap,
                                         extra: #","failure":{"reason":"closeUnconfirmed","needsReview":true}"#))
        XCTAssertEqual(s.startedAt, tap)
        XCTAssertEqual(ShowerActivityAction(s, now: t0), .unconfirmed(startedAt: tap, dismissAfter: 15 * 60))
    }
}
