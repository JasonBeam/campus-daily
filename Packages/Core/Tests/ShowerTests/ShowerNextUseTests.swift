import XCTest
@testable import Core
import CoreTestSupport

/// The next shower over a record that waits for its check (the water was stopped with the
/// controller's own button, say, and 结束 found it idle): the record is kept as it is, never
/// settled or dropped; a controller still in use is let go; the next use verifies the controller
/// again and gets a new authorization. Fakes only: nothing here reaches a controller or the school.
final class ShowerNextUseTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let oldAuthorizationID = "AABBCCDD"
    let next = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x40 + $0) }), authorizationID: "00112233")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
    var consumption: Data { FakeFrames.identity(machine, tail: 9) }
    var oldClose: Data { ShowerFrames.closeCommand(authorizationID: oldAuthorizationID)! }
    var newClose: Data { ShowerFrames.closeCommand(authorizationID: next.authorizationID)! }

    var vault: FlakyShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!

    override func setUp() { reset() }

    func reset() {
        vault = FlakyShowerVault()
        transport = FakeShowerTransport()
        gateway = FakeGateway()
    }

    func engine() throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                         configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
    }

    /// Every kind of record that waits for the user's check.
    var awaitingCheck: [ShowerState] {
        let base = ShowerState(phase: .running, machineID: machine, peripheralID: "PERIPHERAL-A", startedAt: t0.addingTimeInterval(-600),
                               authorizeSent: true, authorizationID: oldAuthorizationID)
        var stopped = base; stopped.stateReviewRequired = true
        var unacknowledged = stopped; unacknowledged.phase = .writePending
        var authorizeUnclear = base; authorizeUnclear.phase = .failed; authorizeUnclear.startedAt = nil; authorizeUnclear.authorizationID = nil
        authorizeUnclear.failure = ShowerFailure(reason: .authorizeUncertain, needsReview: true, error: .uncertain(.lxt6))
        var closeUnconfirmed = base; closeUnconfirmed.phase = .failed; closeUnconfirmed.closeSent = true
        closeUnconfirmed.failure = ShowerFailure(reason: .closeUnconfirmed, needsReview: true, deviceError: .timedOut)
        var settleUnclear = base; settleUnclear.phase = .failed; settleUnclear.consumption = HexCoding.upper(FakeFrames.identity(machine, tail: 9))
        settleUnclear.failure = ShowerFailure(reason: .settleUncertain, needsReview: true, error: .timedOut)
        var settleHeld = settleUnclear; settleHeld.heldConsumption = settleHeld.consumption
        settleHeld.failure = ShowerFailure(reason: .settleUnconfirmed, needsReview: true, settleNotSent: true, settleHeld: true)
        return [stopped, unacknowledged, authorizeUnclear, closeUnconfirmed, settleUnclear, settleHeld]
    }

    // MARK: Fresh next use

    func testNextUseKeepsEveryRecordAwaitingItsCheckAndNeverSettlesIt() async throws {
        for old in awaitingCheck {
            reset()
            try vault.saveShowerState(old)
            let e = try engine()
            let before = await e.state
            XCTAssertTrue(before.canStartNext, "\(old.phase) \(String(describing: old.failure?.reason))")
            transport.script(.frame(identity), .frame(FakeFrames.ack))
            gateway.scriptAuthorize(.ok(next))
            let s = try await e.startNext(binding)

            XCTAssertEqual(try vault.retainedShowers(), [old], "kept as it was")
            XCTAssertNil(try vault.retainedShowers().first?.receipt)
            XCTAssertEqual(s.phase, .running)
            XCTAssertEqual(s.authorizationID, next.authorizationID, "a new authorization")
            XCTAssertFalse(s.stateReviewRequired)
            XCTAssertNil(s.failure)
            XCTAssertNil(s.consumption)
            XCTAssertEqual(gateway.authorizeFrames, [identity], "authorized once, with the fresh identity frame")
            XCTAssertTrue(gateway.settleFrames.isEmpty, "nothing settled")
            XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand, next.payload], "the old authorization is never written again")

            let relaunched = try engine()
            let reread = await relaunched.state
            XCTAssertEqual(reread.phase, .running)
            XCTAssertEqual(reread.authorizationID, next.authorizationID)
            XCTAssertEqual(try vault.retainedShowers(), [old])
        }
    }

    func testTheNextUseEndsWithItsOwnAuthorization() async throws {
        try vault.saveShowerState(awaitingCheck[0])
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(next))
        _ = try await e.startNext(binding)

        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(ShowerReceipt(amount: Money(fen: 42))))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertTrue(transport.writes.contains(newClose))
        XCTAssertFalse(transport.writes.contains(oldClose))
        XCTAssertEqual(gateway.settleFrames, [consumption], "only the new session is settled")
        XCTAssertEqual(try vault.retainedShowers(), [awaitingCheck[0]], "the kept record is untouched")
    }

    func testRecordsKeptOverSeveralNextUsesAllStay() async throws {
        let first = awaitingCheck[0]
        try vault.saveShowerState(first)
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(next))
        _ = try await e.startNext(binding)
        // That shower is stopped with the button too: 结束 finds the controller idle.
        transport.script(.frame(identity))
        let second = try await e.finish(binding)
        XCTAssertTrue(second.stateReviewRequired)

        let other = ShowerAuthorization(machineID: machine, payload: Data(repeating: 7, count: 15), authorizationID: "0A0B0C0D")
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(other))
        _ = try await e.startNext(binding)
        XCTAssertEqual(try vault.retainedShowers(), [first, second.persistable])
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    /// Only a record waiting for its check: an open shower ends with 结束, a settled one starts as usual.
    func testNextUseIsOnlyForARecordAwaitingItsCheck() async throws {
        let open = ShowerState(phase: .running, machineID: machine, peripheralID: "PERIPHERAL-A", startedAt: t0,
                               authorizeSent: true, authorizationID: oldAuthorizationID)
        for record in [open, .idle] {
            reset()
            try vault.saveShowerState(record)
            let e = try engine()
            let before = await e.state
            XCTAssertFalse(before.canStartNext)
            do { _ = try await e.startNext(binding); XCTFail("refused") }
            catch { XCTAssertEqual(error as? ShowerEngineError, .notAllowed) }
            XCTAssertTrue(transport.writes.isEmpty)
            XCTAssertTrue(gateway.authorizeFrames.isEmpty)
        }
    }

    func testNextUseForAnotherDormsMachineIsRefused() async throws {
        try vault.saveShowerState(awaitingCheck[0])
        let e = try engine()
        var moved = binding; moved.machineId = "99999999"
        do { _ = try await e.startNext(moved); XCTFail("refused") }
        catch { XCTAssertEqual(error as? ShowerEngineError, .wrongBinding) }
        XCTAssertTrue(transport.writes.isEmpty)
        XCTAssertEqual(try vault.retainedShowers(), [])
    }

    // MARK: Controller still in use

    func testABusyControllerIsLetGoWithoutKeepingOrAuthorizing() async throws {
        let old = awaitingCheck[3]
        try vault.saveShowerState(old)
        let e = try engine()
        transport.script(.frame(FakeFrames.active))
        let s = try await e.startNext(binding)

        XCTAssertEqual(s.phase, old.phase)
        XCTAssertEqual(s.startedAt, old.startedAt)
        XCTAssertTrue(s.waitingForRelease)
        XCTAssertEqual(s.notice, .device(.busy))
        XCTAssertEqual(try vault.showerState()?.waitingForRelease, true, "saved")
        XCTAssertEqual(try vault.retainedShowers(), [])
        XCTAssertTrue(gateway.authorizeFrames.isEmpty)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand])
        XCTAssertEqual(transport.disconnects, 1, "the link is released")
    }

    func testABusyControllerStaysReleasedAcrossARelaunchUntilTheUserTriesAgain() async throws {
        let old = awaitingCheck[0]
        try vault.saveShowerState(old)
        transport.script(.frame(FakeFrames.active))
        _ = try await engine().startNext(binding)

        let reopened = try engine()
        let restored = await reopened.state
        XCTAssertTrue(restored.waitingForRelease)
        XCTAssertFalse(restored.canFinish)
        do { _ = try await reopened.finish(binding); XCTFail("no close on a record that lost its authorization") }
        catch { XCTAssertEqual(error as? ShowerEngineError, .notAllowed) }
        XCTAssertEqual(transport.disconnects, 1)

        // A check that finds the controller in use lets go of it too and keeps the check.
        transport.script(.frame(FakeFrames.active))
        let probed = try await reopened.review(binding)
        XCTAssertEqual(transport.disconnects, 2)
        XCTAssertTrue(probed.stateReviewRequired)
        XCTAssertFalse(probed.canFinish)
        let kept = try XCTUnwrap(try vault.showerState())

        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(next))
        let s = try await reopened.startNext(binding)
        XCTAssertEqual(try vault.retainedShowers(), [kept])
        XCTAssertEqual(s.phase, .running)
        XCTAssertFalse(s.waitingForRelease)
        XCTAssertEqual(gateway.authorizeFrames.count, 1)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertFalse(transport.writes.contains(oldClose))
    }

    // MARK: Cancelled while it connects or probes

    /// The next use's task cancelled before its probe answer is used (the page went away, say):
    /// whatever the controller answered, nothing is kept, nothing is authorized and the record
    /// stays as it was.
    func testACancelDuringTheConnectOrProbeChangesNothing() async throws {
        enum Way { case connect, probeHangs, probeIdle, probeBusy }
        for way in [Way.connect, .probeHangs, .probeIdle, .probeBusy] {
            reset()
            let old = awaitingCheck[0]
            try vault.saveShowerState(old)
            let e = try engine()
            let box = TaskBox()
            switch way {
            case .connect: transport.scriptConnect(.failure(.interrupted))
            case .probeHangs: transport.script(.hang)
            case .probeIdle: transport.script(.frame(identity), .frame(FakeFrames.ack))
            case .probeBusy: transport.script(.frame(FakeFrames.active))
            }
            transport.onExchange = { if $0 == ShowerFrames.probeCommand { box.cancel() } }
            gateway.scriptAuthorize(.ok(next))
            let (gate, open) = AsyncStream.makeStream(of: Void.self)
            let b = binding
            let task = Task<Void, Never> {
                for await _ in gate { break }
                if way == .connect { box.cancel() }
                _ = try? await e.startNext(b)
            }
            box.set(task)
            open.yield(); open.finish()
            await task.value

            let s = await e.state
            XCTAssertEqual(s.persistable, old, "\(way): the record is unchanged")
            XCTAssertFalse(s.waitingForRelease, "\(way)")
            XCTAssertEqual(try vault.showerState(), old, "\(way): saved as it was")
            XCTAssertEqual(try vault.retainedShowers(), [], "\(way): nothing kept")
            XCTAssertTrue(gateway.authorizeFrames.isEmpty, "\(way): nothing authorized")
            XCTAssertTrue(gateway.settleFrames.isEmpty, "\(way)")
            XCTAssertFalse(transport.writes.contains(oldClose), "\(way)")
            XCTAssertEqual(transport.disconnects, 1, "\(way): the link is let go")
            XCTAssertTrue(s.canStartNext, "\(way): it can be tried again")
        }
    }

    // MARK: Device and storage failures

    func testAnotherControllerIsNeitherKeptNorAuthorized() async throws {
        let old = awaitingCheck[0]
        try vault.saveShowerState(old)
        let e = try engine()
        transport.script(.frame(FakeFrames.identity("99999999")))
        let s = try await e.startNext(binding)
        XCTAssertEqual(s.notice, .wrongDevice)
        XCTAssertEqual(try vault.showerState(), old)
        XCTAssertEqual(try vault.retainedShowers(), [])
        XCTAssertTrue(gateway.authorizeFrames.isEmpty)
        XCTAssertEqual(transport.disconnects, 1)
    }

    func testAControllerOutOfReachChangesNothing() async throws {
        let old = awaitingCheck[0]
        try vault.saveShowerState(old)
        let e = try engine()
        transport.scriptConnect(.failure(.notFound))
        let s = try await e.startNext(binding)
        XCTAssertEqual(s.notice, .device(.notFound))
        XCTAssertEqual(try vault.showerState(), old)
        XCTAssertEqual(try vault.retainedShowers(), [])
        XCTAssertTrue(gateway.authorizeFrames.isEmpty)
    }

    func testTheRecordIsNeverLostWhenKeepingOrSavingFails() async throws {
        for keepFails in [true, false] {
            reset()
            let old = awaitingCheck[4]
            try vault.saveShowerState(old)
            vault.failRetain = keepFails
            vault.failSave = !keepFails
            let e = try engine()
            transport.script(.frame(identity))
            do { _ = try await e.startNext(binding); XCTFail("storage error") }
            catch { XCTAssertEqual(error as? ShowerEngineError, .storage) }
            let blocked = await e.storageBlocked
            XCTAssertTrue(blocked)
            XCTAssertTrue(gateway.authorizeFrames.isEmpty)
            XCTAssertTrue(gateway.settleFrames.isEmpty)
            vault.failSave = false
            XCTAssertEqual(try vault.showerState(), old, "the record in place is the old one")
            XCTAssertEqual(try vault.retainedShowers(), keepFails ? [] : [old])
        }
    }

    // MARK: Authorization outcomes are not replayed

    func testARefusedOrUnclearNewAuthorizationIsNotSentAgain() async throws {
        for failure in [ServiceError.badRequest(.lxt6), .timedOut] {
            reset()
            let old = awaitingCheck[3]
            try vault.saveShowerState(old)
            let e = try engine()
            transport.script(.frame(identity))
            gateway.scriptAuthorize(.fail(failure))
            let s = try await e.startNext(binding)
            XCTAssertEqual(try vault.retainedShowers(), [old])
            XCTAssertEqual(gateway.authorizeFrames.count, 1)
            XCTAssertTrue(gateway.settleFrames.isEmpty)
            XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand])
            if ShowerReducer.isDefiniteAuthorizeRefusal(failure) {
                XCTAssertEqual(try vault.showerState()?.phase, .idle, "nothing issued")
            } else {
                XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
                XCTAssertEqual(try vault.showerState()?.failure?.reason, .authorizeUncertain, "waits for its own check")
            }
        }
    }

    // MARK: Records from earlier builds

    func testARecordFromAnEarlierBuildDaysAgoCanStartTheNextUse() async throws {
        for days in [1.0, 7.0] {
            reset()
            var old = awaitingCheck[5]
            old.startedAt = t0.addingTimeInterval(-days * 86_400)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
            json.removeValue(forKey: "waitingForRelease")
            let legacy = try JSONSerialization.data(withJSONObject: json)
            try vault.store.write(legacy, for: .showerSession)
            let saved = try XCTUnwrap(try vault.showerState())
            XCTAssertFalse(saved.waitingForRelease)

            let e = try engine()
            transport.script(.frame(identity), .frame(FakeFrames.ack))
            gateway.scriptAuthorize(.ok(next))
            let s = try await e.startNext(binding)
            XCTAssertEqual(try vault.retainedShowers(), [saved])
            XCTAssertEqual(s.phase, .running)
            XCTAssertGreaterThan(try XCTUnwrap(s.startedAt), try XCTUnwrap(saved.startedAt))
            XCTAssertTrue(gateway.settleFrames.isEmpty)
        }
    }

    func testAVaultThatCannotKeepRecordsRefusesTheNextUse() async throws {
        struct Plain: ShowerVault {
            let inner = StoredShowerVault(store: InMemorySecureStore())
            func binding() throws -> ShowerBinding? { try inner.binding() }
            func saveBinding(_ b: ShowerBinding?) throws { try inner.saveBinding(b) }
            func showerState() throws -> ShowerState? { try inner.showerState() }
            func saveShowerState(_ s: ShowerState?) throws { try inner.saveShowerState(s) }
        }
        let plain = Plain()
        XCTAssertEqual(try plain.retainedShowers(), [])
        XCTAssertThrowsError(try plain.retainShower(awaitingCheck[0]))
    }
}

/// `StoredShowerVault` whose writes can be made to fail.
final class FlakyShowerVault: ShowerVault, @unchecked Sendable {
    // @unchecked: flags guarded by `lock`.
    let store = InMemorySecureStore()
    private let lock = NSLock()
    private var _failRetain = false
    private var _failSave = false
    var failRetain: Bool { get { lock.withLock { _failRetain } } set { lock.withLock { _failRetain = newValue } } }
    var failSave: Bool { get { lock.withLock { _failSave } } set { lock.withLock { _failSave = newValue } } }
    private var inner: StoredShowerVault { StoredShowerVault(store: store) }

    func binding() throws -> ShowerBinding? { try inner.binding() }
    func saveBinding(_ binding: ShowerBinding?) throws { try inner.saveBinding(binding) }
    func showerState() throws -> ShowerState? { try inner.showerState() }
    func saveShowerState(_ state: ShowerState?) throws {
        if failSave { throw StorageError(operation: "save", status: -1) }
        try inner.saveShowerState(state)
    }
    func retainedShowers() throws -> [ShowerState] { try inner.retainedShowers() }
    func retainShower(_ state: ShowerState) throws {
        if failRetain { throw StorageError(operation: "retain", status: -1) }
        try inner.retainShower(state)
    }
}
