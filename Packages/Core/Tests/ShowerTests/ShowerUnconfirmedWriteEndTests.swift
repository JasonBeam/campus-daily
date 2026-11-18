import XCTest
@testable import Core
import CoreTestSupport

/// 结束 over an authorization write the controller did not confirm (`writePending`): the close
/// goes out when the controller runs, and only the end data that close returns is settled, once.
/// Without that data nothing is settled; nothing is ever sent twice, not on a second tap, a
/// relaunch or an answer that comes late. Records an older build held back are never settled.
final class ShowerUnconfirmedWriteEndTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let receipt = ShowerReceipt(amount: Money(fen: 163))
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
    var consumption: Data { FakeFrames.identity(machine, tail: 9) }
    var close: Data { ShowerFrames.closeCommand(authorizationID: "001122FF")! }

    var vault: StoredShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!

    override func setUp() { reset() }

    func reset() {
        vault = StoredShowerVault(store: InMemorySecureStore())
        transport = FakeShowerTransport()
        gateway = FakeGateway()
    }

    func engine(_ v: ShowerVault? = nil) throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: v ?? vault,
                         configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
    }

    var closes: Int { transport.writes.filter { $0 == close }.count }

    /// Started; the write answered with something other than the ack.
    func unconfirmed(_ e: ShowerEngine) async throws {
        transport.script(.frame(identity), .frame(Data([0x12, 0x34])))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding)
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertFalse(s.authorizationNotWritten)
    }

    func testEndingAnUnconfirmedWriteClosesAndSettlesTheCloseReply() async throws {
        let e = try engine()
        try await unconfirmed(e)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand, auth.payload, ShowerFrames.probeCommand, close])
        XCTAssertEqual(gateway.settleFrames, [consumption], "the close's reply, as it came")
        XCTAssertEqual(gateway.settleBindings, [binding])
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(done.receipt, receipt)
        XCTAssertEqual(done.consumption, HexCoding.upper(consumption))
    }

    func testAnUnconfirmedWriteFoundRunningThenEndedSettlesOnce() async throws {
        let e = try engine()
        try await unconfirmed(e)
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        XCTAssertEqual(probed.phase, .running)
        XCTAssertFalse(probed.holdSettle)
        XCTAssertFalse(try XCTUnwrap(try vault.showerState()).holdSettle)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(gateway.settleFrames, [consumption])
        XCTAssertEqual(closes, 1)
    }

    /// No end data from the close (busy, unreadable, another machine, no answer): never settled,
    /// kept for the check, and 结束 can't send the close again.
    func testAnUnconfirmedWriteCloseReplyBusyOrUnreadableNeverSettles() async throws {
        let cases: [(FakeShowerTransport.Reply, ShowerFailureReason)] = [
            (.frame(FakeFrames.active), .closeBusy),
            (.frame(Data([0x12, 0x34, 0x56])), .closeUnconfirmed),
            (.frame(FakeFrames.identity("99999999", tail: 9)), .closeUnconfirmed),
            (.fail(.timedOut), .closeUnconfirmed),
            (.fail(.disconnected), .closeUnconfirmed),
        ]
        for (reply, reason) in cases {
            reset()
            let e = try engine()
            try await unconfirmed(e)
            transport.script(.frame(FakeFrames.active), reply)
            gateway.scriptSettle(.ok(receipt))
            let s = try await e.finish(binding)
            XCTAssertEqual(s.phase, .failed, "\(reply)")
            XCTAssertEqual(s.failure?.reason, reason, "\(reply)")
            XCTAssertNil(s.consumption, "\(reply)")
            XCTAssertTrue(gateway.settleFrames.isEmpty, "\(reply)")
            XCTAssertFalse(s.canRetrySettle)
            await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
            XCTAssertEqual(closes, 1, "\(reply)")
        }
    }

    /// Two 结束 at once (the page, the lock screen, Siri): the second is turned away while the
    /// first runs; one close, one settlement.
    func testDoubleEndSendsOneCloseAndOneSettle() async throws {
        let e = try engine()
        try await unconfirmed(e)
        let (gate, open) = AsyncStream<Void>.makeStream()
        transport.script(.after(gate, FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt), .ok(receipt))
        let b = binding
        let first = Task { try await e.finish(b) }
        await eventually { await e.state.phase == .closing }
        await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .busy) }
        open.yield(); open.finish()
        let done = try await first.value
        XCTAssertEqual(done.phase, .done)
        await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(gateway.settleFrames, [consumption])
    }

    /// The app stopped while the settlement was out: the relaunch keeps it for the check and
    /// nothing sends it again, by hand or by the automatic check.
    func testRelaunchDuringSettleNeverResends() async throws {
        let e = try engine()
        try await unconfirmed(e)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.hang)
        let b = binding
        let running = Task { _ = try? await e.finish(b) }
        await eventually { [vault] in (try? vault!.showerState())??.phase == .settling }
        XCTAssertEqual(gateway.settleFrames.count, 1)

        let relaunched = try engine()
        let s = await relaunched.state
        XCTAssertEqual(s.phase, .failed)
        XCTAssertEqual(s.failure?.reason, .settleUnconfirmed)
        XCTAssertEqual(s.failure?.settleNotSent, false, "it may have left")
        await XCTAssertThrowsErrorAsync(try await relaunched.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        await XCTAssertThrowsErrorAsync(try await relaunched.autoReview(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        running.cancel()
        _ = await running.value
        XCTAssertEqual(gateway.settleFrames.count, 1)
        XCTAssertEqual(closes, 1)
    }

    /// A settlement answer that comes once the record is failed changes nothing.
    func testALateSettledEventIsIgnoredOnceFailed() {
        let failed = ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                                 closeSent: true, consumption: HexCoding.upper(consumption),
                                 failure: ShowerFailure(reason: .settleUncertain, needsReview: true, error: .uncertain(.lxt6)))
        for event in [ShowerEvent.settled(receipt, at: t0), .settleFailed(.timedOut), .closeReplied(consumption), .cancelledBeforeSend] {
            let (next, fx) = ShowerReducer.reduce(failed, event)
            XCTAssertEqual(next, failed, "\(event)")
            XCTAssertEqual(fx, [], "\(event)")
        }
    }

    /// The close's reply settles once: the same reply again, while settling or after, sends
    /// nothing more.
    func testTheSameCloseReplyTwiceSettlesOnce() {
        let closing = ShowerState(phase: .closing, machineID: machine, peripheralID: "P", startedAt: t0, authorizeSent: true,
                                  authorizationID: "001122FF", closingFrom: .writePending, closeSent: true)
        let (settling, fx) = ShowerReducer.reduce(closing, .closeReplied(consumption))
        XCTAssertEqual(settling.phase, .settling)
        XCTAssertEqual(fx.filter { if case .settle = $0 { return true }; return false }, [.settle(frame: consumption)])
        let failed = ShowerReducer.reduce(settling, .settleFailed(.timedOut)).0
        let done = ShowerReducer.reduce(settling, .settled(receipt, at: t0)).0
        for s in [settling, failed, done] {
            let (next, again) = ShowerReducer.reduce(s, .closeReplied(consumption))
            XCTAssertEqual(next, s, "\(s.phase)")
            XCTAssertEqual(again, [], "\(s.phase)")
        }
    }

    /// The settling record can't be saved: the settlement never leaves.
    func testAStorageFailureBeforeTheSettlementSendsNothing() async throws {
        let flaky = FlakyVault(inner: vault) { $0?.phase == .settling }
        let e = try engine(flaky)
        try await unconfirmed(e)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .storage) }
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertEqual(closes, 1)
    }

    /// An older build's record that was to hold its end data: after the update its end settles
    /// as any other.
    func testOldHeldRecordIsSettledOnEndAfterUpdate() async throws {
        let old = ShowerState(phase: .writePending, machineID: machine, peripheralID: "P", startedAt: t0, authorizeSent: true,
                              authorizationID: "001122FF", holdSettle: true)
        try vault.saveShowerState(old)
        let e = try engine()
        let st1 = await e.state
        XCTAssertFalse(st1.holdSettle)
        XCTAssertFalse(try XCTUnwrap(try vault.showerState()).holdSettle, "saved without it")
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(gateway.settleFrames, [consumption])

        // Also one an older build left mid-close (not sent yet): back on the timer, then settled.
        reset()
        var closing = old
        closing.phase = .closing; closing.closingFrom = .writePending; closing.closeSent = false
        try vault.saveShowerState(closing)
        let e2 = try engine()
        let st2 = await e2.state
        XCTAssertEqual(st2.phase, .writePending)
        let st3 = await e2.state
        XCTAssertFalse(st3.holdSettle)
    }

    /// End data an older build held back is never settled: not by its retry, not by a relaunch,
    /// also when only the frame says it was held.
    func testOldHeldFailureIsNeverSettled() async throws {
        let hex = HexCoding.upper(consumption)
        let flagged = ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                                  closeSent: true, consumption: hex,
                                  failure: ShowerFailure(reason: .settleUnconfirmed, needsReview: true, settleNotSent: true, settleHeld: true),
                                  heldConsumption: hex)
        var frameOnly = flagged
        frameOnly.failure = ShowerFailure(reason: .settleUncertain, needsReview: true)
        var flagOnly = flagged
        flagOnly.heldConsumption = nil
        flagOnly.failure = ShowerFailure(reason: .settleRefused, needsReview: true, settleHeld: true)
        for record in [flagged, frameOnly, flagOnly] {
            reset()
            XCTAssertFalse(record.canRetrySettle, "\(String(describing: record.failure))")
            var armed = record
            armed.settleRetryArmed = true
            XCTAssertEqual(ShowerReducer.reduce(record, .requestSettleRetry).1, [])
            XCTAssertFalse(ShowerReducer.reduce(record, .requestSettleRetry).0.settleRetryArmed)
            XCTAssertEqual(ShowerReducer.reduce(armed, .confirmSettleRetry).1, [], "an arm saved by an older build sends nothing")
            try vault.saveShowerState(record)
            let e = try engine()
            await XCTAssertThrowsErrorAsync(try await e.requestSettleRetry()) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
            await XCTAssertThrowsErrorAsync(try await e.confirmSettleRetry(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
            await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
            XCTAssertTrue(gateway.settleFrames.isEmpty)
            XCTAssertTrue(transport.writes.isEmpty)
            XCTAssertEqual(try vault.showerState()?.failure, record.failure, "kept as it was")
        }
    }
}
