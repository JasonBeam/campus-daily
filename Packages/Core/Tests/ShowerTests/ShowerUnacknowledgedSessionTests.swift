import XCTest
@testable import Core
import CoreTestSupport

/// The consumption frame names only the controller (`55`, machine id, 15 bytes nothing is known
/// to tie to an authorization), so it can't show whose session the close ended. Only the
/// controller's acknowledgement of our authorization write shows the session was ours: without
/// it, an `A5` at 结束 may be someone else's water, and what the close returns waits for the
/// user's two-tap settle instead of being settled by itself.
final class ShowerUnacknowledgedSessionTests: XCTestCase {
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

    /// The authorization went out but the controller never acknowledged it.
    func unacknowledged(_ reply: FakeShowerTransport.Reply) async throws -> ShowerEngine {
        let e = try engine()
        transport.script(.frame(identity), reply)
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding)
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertFalse(s.authorizationNotWritten)
        return e
    }

    func assertHeld(_ held: ShowerState, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(transport.writes.contains(close), "the close is still sent (\(label))", file: file, line: line)
        XCTAssertTrue(gateway.settleFrames.isEmpty, "not settled by itself (\(label))", file: file, line: line)
        XCTAssertEqual(held.phase, .failed, label, file: file, line: line)
        XCTAssertEqual(held.failure?.reason, .settleUnconfirmed, label, file: file, line: line)
        XCTAssertEqual(held.failure?.settleNotSent, true, label, file: file, line: line)
        XCTAssertEqual(held.consumption, HexCoding.upper(consumption), "kept for the retry (\(label))", file: file, line: line)
        XCTAssertTrue(held.canRetrySettle, label, file: file, line: line)
        XCTAssertEqual(ShowerPage(held)?.phase, .stopped, label, file: file, line: line)
    }

    func testAnEndWithoutTheControllersAcknowledgementIsNotSettledByItself() async throws {
        for reply in [FakeShowerTransport.Reply.fail(.timedOut), .fail(.disconnected), .frame(Data([0xAA, 0]))] {
            reset()
            let e = try await unacknowledged(reply)
            transport.script(.frame(FakeFrames.active), .frame(consumption))
            gateway.scriptSettle(.ok(receipt))
            let held = try await e.finish(binding)
            assertHeld(held, "\(reply)")
            XCTAssertEqual(try vault.showerState()?.consumption, HexCoding.upper(consumption), "persisted")

            // The usual two taps send it once.
            _ = try await e.requestSettleRetry()
            let done = try await e.confirmSettleRetry(binding)
            XCTAssertEqual(done.phase, .done)
            XCTAssertEqual(gateway.settleFrames, [consumption])
        }
    }

    /// A probe that finds water running proves nothing about whose it is: back on the timer,
    /// the end still waits for the user.
    func testAProbeThatFindsWaterRunningDoesNotCountAsTheAcknowledgement() async throws {
        let e = try await unacknowledged(.fail(.timedOut))
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        XCTAssertEqual(probed.phase, .running)

        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        assertHeld(try await e.finish(binding), "after the probe")
    }

    func testTheHoldSurvivesARelaunchAndACloseThatWasNotSent() async throws {
        let e = try await unacknowledged(.fail(.timedOut))
        // The first 结束 doesn't reach the controller: back on the timer.
        transport.scriptConnect(.failure(.notFound))
        let back = try await e.finish(binding)
        XCTAssertEqual(back.phase, .writePending)

        let relaunched = try engine()
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        assertHeld(try await relaunched.finish(binding), "relaunched")
    }

    /// An acknowledged authorization is ours: its end settles by itself, as before.
    func testAnAcknowledgedSessionStillSettlesByItself() async throws {
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let started = try await e.start(binding)
        XCTAssertEqual(started.phase, .running)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(gateway.settleFrames, [consumption])
    }
}
