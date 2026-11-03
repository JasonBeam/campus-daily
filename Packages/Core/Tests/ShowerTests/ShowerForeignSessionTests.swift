import XCTest
@testable import Core
import CoreTestSupport

/// An `A5` (water running) that is most likely someone else's session never gets closed or
/// settled under this record without the user: after a close that most likely took, the next
/// consumption frame is kept for a manual settle; with an authorization that provably never
/// reached the controller, no close is sent at all.
final class ShowerForeignSessionTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let close = Data([0xAC, 0x55, 0x44, 0x77, 0xAA])
    let receipt = ShowerReceipt(amount: Money(fen: 163))
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
    var consumption: Data { FakeFrames.identity(machine, tail: 9) }

    var vault: StoredShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!

    override func setUp() { reset() }

    func reset() {
        vault = StoredShowerVault(store: InMemorySecureStore())
        transport = FakeShowerTransport()
        gateway = FakeGateway()
    }

    func engine() throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                         configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
    }

    func running() async throws -> ShowerEngine {
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding)
        XCTAssertEqual(s.phase, .running)
        return e
    }

    /// The two ways into an unconfirmed close: the answer to the close was lost, or it came
    /// back with another machine's identity.
    func closeUnconfirmed(byWrongIdentity: Bool) async throws -> ShowerEngine {
        let e = try await running()
        transport.script(.frame(FakeFrames.active), byWrongIdentity ? .frame(FakeFrames.identity("99999999", tail: 9)) : .fail(.timedOut))
        let s = try await e.finish(binding)
        XCTAssertEqual(s.failure?.reason, .closeUnconfirmed)
        return e
    }

    // MARK: Back from an unconfirmed close

    func testAfterAnUnconfirmedCloseTheNextConsumptionIsKeptNotSettled() async throws {
        for wrongIdentity in [false, true] {
            reset()
            let e = try await closeUnconfirmed(byWrongIdentity: wrongIdentity)
            transport.script(.frame(FakeFrames.active))
            let back = try await e.review(binding)
            XCTAssertEqual(back.phase, .running, "\(wrongIdentity)")
            XCTAssertTrue(back.canFinish)

            transport.script(.frame(FakeFrames.active), .frame(consumption))
            gateway.scriptSettle(.ok(receipt))
            let held = try await e.finish(binding)
            XCTAssertTrue(gateway.settleFrames.isEmpty, "not settled by itself (\(wrongIdentity))")
            XCTAssertEqual(held.phase, .failed)
            XCTAssertEqual(held.failure?.needsReview, true)
            XCTAssertEqual(held.consumption, HexCoding.upper(consumption), "kept for the retry")
            XCTAssertTrue(held.canRetrySettle)
            XCTAssertTrue(held.canResolveManually)
            XCTAssertEqual(ShowerPage(held)?.phase, .unsure)
            XCTAssertEqual(try vault.showerState()?.consumption, HexCoding.upper(consumption), "persisted")

            // The usual two taps send it once.
            _ = try await e.requestSettleRetry()
            XCTAssertTrue(gateway.settleFrames.isEmpty)
            let done = try await e.confirmSettleRetry(binding)
            XCTAssertEqual(done.phase, .done)
            XCTAssertEqual(gateway.settleFrames, [consumption])
        }
    }

    /// The hold is only for a session that came back from an unconfirmed close.
    func testAnOrdinaryEndStillSettlesByItself() async throws {
        let e = try await running()
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(gateway.settleFrames, [consumption])
    }

    func testTheHoldSurvivesARelaunch() async throws {
        let e = try await closeUnconfirmed(byWrongIdentity: false)
        transport.script(.frame(FakeFrames.active))
        _ = try await e.review(binding)

        let relaunched = try engine()
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        let held = try await relaunched.finish(binding)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertTrue(held.canRetrySettle)
    }

    // MARK: Authorization never written

    func writeNeverApplied() async throws -> ShowerEngine {
        let e = try engine()
        transport.script(.frame(identity), .notSent(.disconnected))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding)
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertTrue(s.authorizationNotWritten)
        return e
    }

    func testWaterRunningOnAControllerOurAuthorizationNeverReachedIsNotClosed() async throws {
        let e = try await writeNeverApplied()
        transport.script(.frame(FakeFrames.active))
        let back = try await e.finish(binding)
        XCTAssertFalse(transport.writes.contains(close), "someone else's water is not closed")
        XCTAssertEqual(back.phase, .writePending)
        XCTAssertFalse(back.closeSent)
        XCTAssertNil(back.failure)
        XCTAssertTrue(back.authorizationNotWritten)
        XCTAssertEqual(back.notice, .inUseByOther)
        XCTAssertEqual(ShowerEndFailure(back.notice), .inUseByOther)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertEqual(try vault.showerState()?.phase, .writePending)

        // Once it is free, 结束 ends the record as before: our authorization never ran water.
        transport.script(.frame(identity))
        let idle = try await e.finish(binding)
        XCTAssertEqual(idle.phase, .idle)
        XCTAssertFalse(transport.writes.contains(close))
    }

    /// A probe from Settings that finds water running does not make that water ours either.
    func testAProbeThatFindsWaterRunningKeepsTheAuthorizationUnwritten() async throws {
        let e = try await writeNeverApplied()
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        XCTAssertEqual(probed.phase, .writePending)
        XCTAssertTrue(probed.authorizationNotWritten)
        XCTAssertEqual(probed.notice, .inUseByOther, "the probe says whose water it is")
        XCTAssertFalse(probed.stateReviewRequired)
        XCTAssertFalse(transport.writes.contains(close))

        transport.script(.frame(FakeFrames.active))
        let back = try await e.finish(binding)
        XCTAssertFalse(transport.writes.contains(close))
        XCTAssertEqual(back.notice, .inUseByOther)
    }

    /// 再查一次水控 that finds water running on such a session: the timer comes up with the
    /// same line 结束 gives, not as if the water were ours.
    func testARecheckThatFindsWaterRunningSaysItIsSomeoneElses() async throws {
        // The needs-check face over such a session (an earlier build's probe left it there).
        try vault.saveShowerState(ShowerState(phase: .writePending, machineID: machine, startedAt: t0, authorizeSent: true,
                                              authorizationID: "001122FF", stateReviewRequired: true,
                                              authorizationNotWritten: true))
        let e = try engine()
        var flow = ShowerPageFlow(record: await e.state, presented: true)
        XCTAssertEqual(flow.page?.phase, .needsCheck)
        flow = ShowerPageFlow.reduce(flow, .recheckTapped).0
        XCTAssertTrue(flow.rechecking)
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        flow = ShowerPageFlow.reduce(flow, .record(probed)).0
        flow = ShowerPageFlow.reduce(flow, .recheckReturned(ShowerRecheckResult(after: probed))).0
        XCTAssertEqual(flow.page?.phase, .running)
        XCTAssertEqual(flow.endFailed, .inUseByOther)
    }

    /// A probe that finds the controller idle with our id: our authorization never ran water,
    /// so the record ends the way 结束 ends it, with no check and no settlement.
    func testAProbeThatFindsTheControllerIdleEndsTheRecord() async throws {
        let e = try await writeNeverApplied()
        transport.script(.frame(identity))
        let probed = try await e.review(binding)
        XCTAssertEqual(probed.phase, .idle)
        XCTAssertFalse(probed.stateReviewRequired)
        XCTAssertNil(probed.failure)
        XCTAssertEqual(try vault.showerState()?.phase, .idle)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertFalse(transport.writes.contains(close))
    }

    /// The idle exit is for a session still waiting on its write, as 结束 checks
    /// `from == .writePending`: a running record with the flag (a later write may have run
    /// water) is kept for the check, never ended by a probe.
    func testAProbeOfARunningRecordDoesNotEndItEvenWithTheFlag() {
        let running = ShowerState(phase: .running, machineID: "11223344", peripheralID: "P", startedAt: Date(),
                                  authorizeSent: true, authorizationID: "001122FF", reviewing: true,
                                  authorizationNotWritten: true)
        let (s, fx) = ShowerReducer.reduce(running, .probeReplied(FakeFrames.identity("11223344")))
        XCTAssertEqual(s.phase, .running)
        XCTAssertTrue(s.stateReviewRequired)
        XCTAssertEqual(s.notice, .notActive)
        XCTAssertEqual(fx, [.releaseDevice])

        var pending = running
        pending.phase = .writePending
        XCTAssertEqual(ShowerReducer.reduce(pending, .probeReplied(FakeFrames.identity("11223344"))).0.phase, .idle)
    }
}
