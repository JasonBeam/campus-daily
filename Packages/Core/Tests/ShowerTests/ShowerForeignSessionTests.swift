//
//  ShowerForeignSessionTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import XCTest
@testable import Core
import CoreTestSupport

/// An `A5` (water running) found after a close that went out is never closed again or settled
/// under this record. With an authorization that provably never reached the controller, 结束
/// closes the running water and settles the close's reply, as for any session.
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
        let s = try await e.start(binding, permit: ShowerStartPermit())
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

    /// Water found running after an unconfirmed close may be anyone's: the check never takes
    /// the record back to the timer, so no second close goes out and nothing is settled.
    func testAfterAnUnconfirmedCloseWaterFoundRunningCannotBeEndedAgain() async throws {
        for wrongIdentity in [false, true] {
            reset()
            let e = try await closeUnconfirmed(byWrongIdentity: wrongIdentity)
            transport.script(.frame(FakeFrames.active))
            let probed = try await e.review(binding)
            XCTAssertEqual(probed.phase, .failed, "\(wrongIdentity)")
            XCTAssertEqual(probed.failure?.reason, .closeUnconfirmed)
            XCTAssertEqual(probed.notice, .inUseByOther)
            XCTAssertFalse(probed.canFinish)
            XCTAssertEqual(ShowerPage(probed)?.phase, .stopped)
            await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
            XCTAssertEqual(transport.writes.filter { $0 == close }.count, 1, "one close in all (\(wrongIdentity))")
            XCTAssertTrue(gateway.settleFrames.isEmpty)
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

    func testARelaunchDoesNotReopenItEither() async throws {
        let e = try await closeUnconfirmed(byWrongIdentity: false)
        transport.script(.frame(FakeFrames.active))
        _ = try await e.review(binding)

        let relaunched = try engine()
        await XCTAssertThrowsErrorAsync(try await relaunched.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertEqual(transport.writes.filter { $0 == close }.count, 1)
    }

    // MARK: Authorization never written

    func writeNeverApplied() async throws -> ShowerEngine {
        let e = try engine()
        transport.script(.frame(identity), .notSent(.disconnected))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding, permit: ShowerStartPermit())
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertTrue(s.authorizationNotWritten)
        return e
    }

    /// 结束 finds water running on a controller our write provably never reached: it closes it
    /// with this record's authorization and settles what that close returns, once (the owner's
    /// choice: the water may not be this session's, and nothing in the frame says whose it is).
    func testEndingANeverWrittenAuthorizationOverRunningWaterClosesAndSettles() async throws {
        let e = try await writeNeverApplied()
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(transport.writes.filter { $0 == close }.count, 1, "closed with this record's authorization")
        XCTAssertEqual(transport.writes.last, ShowerFrames.closeCommand(authorizationID: "001122FF"))
        XCTAssertEqual(gateway.settleFrames, [consumption], "the close's reply")
        XCTAssertEqual(gateway.settleBindings, [binding])
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(done.receipt, receipt)
    }

    /// Idle at 结束: our authorization never ran water, so the record ends with no charge.
    func testANeverWrittenAuthorizationReadingIdleEndsWithoutCharge() async throws {
        let e = try await writeNeverApplied()
        transport.script(.frame(identity))
        let idle = try await e.finish(binding)
        XCTAssertEqual(idle.phase, .idle)
        XCTAssertFalse(transport.writes.contains(close))
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    /// No end data from that close: nothing settled, kept for the check, never closed again.
    func testANeverWrittenAuthorizationWithBadCloseReplyDoesNotSettle() async throws {
        for reply in [FakeShowerTransport.Reply.frame(FakeFrames.active), .frame(Data([0x12, 0x34])), .fail(.timedOut)] {
            reset()
            let e = try await writeNeverApplied()
            transport.script(.frame(FakeFrames.active), reply)
            gateway.scriptSettle(.ok(receipt))
            let s = try await e.finish(binding)
            XCTAssertEqual(s.phase, .failed, "\(reply)")
            XCTAssertEqual(s.failure?.reason.isUnsureClose, true, "\(reply)")
            XCTAssertTrue(gateway.settleFrames.isEmpty, "\(reply)")
            await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
            XCTAssertEqual(transport.writes.filter { $0 == close }.count, 1)
        }
    }

    /// A probe from Settings that finds water running says so without calling it someone else's:
    /// the record stays waiting on its write (not the confirmed timer), the automatic check
    /// leaves it alone, and only `AA` went out.
    func testAProbeOverANeverWrittenAuthorizationStaysPending() async throws {
        let e = try await writeNeverApplied()
        let writes = transport.writes.count
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        XCTAssertEqual(probed.phase, .writePending)
        XCTAssertTrue(probed.authorizationNotWritten)
        XCTAssertEqual(probed.notice, .waterRunning)
        XCTAssertNil(ShowerEndFailure(probed.notice), "not an end that failed")
        XCTAssertFalse(probed.stateReviewRequired)
        XCTAssertTrue(probed.canFinish)
        XCTAssertEqual(Array(transport.writes.dropFirst(writes)), [ShowerFrames.probeCommand])
        XCTAssertFalse(ShowerAutoReview.eligible(probed))
        await XCTAssertThrowsErrorAsync(try await e.autoReview(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    /// 再查一次 that finds water running on such a session once it showed stopped: it stays
    /// over (水控有人在用), never back on the old session's timer.
    func testARecheckThatFindsWaterRunningOnAStoppedSessionNeverResumesIt() async throws {
        // Stopped, and the next start found the controller in use (an earlier build's probe left it there).
        try vault.saveShowerState(ShowerState(phase: .writePending, machineID: machine, peripheralID: "P", startedAt: t0, authorizeSent: true,
                                              authorizationID: "001122FF", stateReviewRequired: true,
                                              authorizationNotWritten: true, waitingForRelease: true))
        let e = try engine()
        var flow = ShowerPageFlow(record: await e.state, presented: true)
        XCTAssertEqual(flow.page?.phase, .stopped)
        flow = ShowerPageFlow.reduce(flow, .recheckTapped).0
        XCTAssertTrue(flow.rechecking)
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        flow = ShowerPageFlow.reduce(flow, .record(probed)).0
        flow = ShowerPageFlow.reduce(flow, .recheckReturned(ShowerRecheckResult(after: probed))).0
        XCTAssertEqual(flow.page?.phase, .stopped)
        XCTAssertTrue(flow.foundInUse)
        XCTAssertFalse(probed.canFinish)
        XCTAssertFalse(transport.writes.contains(ShowerFrames.closeCommand(authorizationID: "001122FF")!))
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
