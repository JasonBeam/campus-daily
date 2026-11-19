import XCTest
@testable import Core
import CoreTestSupport

/// The controller did not acknowledge the authorization write (no `AA` ack, a timeout, a lost
/// link): it may have been applied. 结束 then ends it as any session: the close goes out when the
/// controller runs (`A5`), and the end data the close returns is settled once, by itself.
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
        let s = try await e.start(binding, permit: ShowerStartPermit())
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertFalse(s.authorizationNotWritten)
        return e
    }

    func assertSettledOnce(_ done: ShowerState, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(transport.writes.filter { $0 == close }.count, 1, "one close (\(label))", file: file, line: line)
        XCTAssertEqual(gateway.settleFrames, [consumption], "the close's own reply, settled once (\(label))", file: file, line: line)
        XCTAssertEqual(gateway.settleBindings.map(\.studentId), [binding.studentId], label, file: file, line: line)
        XCTAssertEqual(done.phase, .done, label, file: file, line: line)
        XCTAssertEqual(done.receipt, receipt, label, file: file, line: line)
        XCTAssertFalse(done.holdSettle, label, file: file, line: line)
        XCTAssertNil(done.heldConsumption, label, file: file, line: line)
    }

    func testAnEndWithoutTheControllersAcknowledgementSettlesByItself() async throws {
        for reply in [FakeShowerTransport.Reply.fail(.timedOut), .fail(.disconnected), .frame(Data([0xAA, 0]))] {
            reset()
            let e = try await unacknowledged(reply)
            transport.script(.frame(FakeFrames.active), .frame(consumption))
            gateway.scriptSettle(.ok(receipt))
            assertSettledOnce(try await e.finish(binding), "\(reply)")
            XCTAssertEqual(try vault.showerState()?.phase, .done, "persisted")
        }
    }

    /// A probe that finds water running takes it back to the timer; its end settles once.
    func testAProbeThatFindsWaterRunningThenAnEndSettlesOnce() async throws {
        let e = try await unacknowledged(.fail(.timedOut))
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        XCTAssertEqual(probed.phase, .running)
        XCTAssertFalse(probed.holdSettle)

        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        assertSettledOnce(try await e.finish(binding), "after the probe")
    }

    func testAnEndAfterARelaunchAndACloseThatWasNotSentSettlesOnce() async throws {
        let e = try await unacknowledged(.fail(.timedOut))
        // The first 结束 doesn't reach the controller: back on the timer.
        transport.scriptConnect(.failure(.notFound))
        let back = try await e.finish(binding)
        XCTAssertEqual(back.phase, .writePending)

        let relaunched = try engine()
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        assertSettledOnce(try await relaunched.finish(binding), "relaunched")
    }

    /// An acknowledged authorization is ours: its end settles by itself, as before.
    func testAnAcknowledgedSessionStillSettlesByItself() async throws {
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let started = try await e.start(binding, permit: ShowerStartPermit())
        XCTAssertEqual(started.phase, .running)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(gateway.settleFrames, [consumption])
    }
}
