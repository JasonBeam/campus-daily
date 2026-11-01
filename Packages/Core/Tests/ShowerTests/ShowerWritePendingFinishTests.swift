import XCTest
@testable import Core
import CoreTestSupport

/// 结束 on a session whose authorization write was not confirmed, when the controller reads
/// idle: the write may still have been applied (only its answer lost), so the record waits for
/// a check. Only a write that provably never went out ends without one.
final class ShowerWritePendingFinishTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let close = Data([0xAC, 0x55, 0x44, 0x77, 0xAA])
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }

    var vault: StoredShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!
    var hooks: RecordingHooks!

    override func setUp() { reset() }

    func reset() {
        vault = StoredShowerVault(store: InMemorySecureStore())
        transport = FakeShowerTransport()
        gateway = FakeGateway()
        hooks = RecordingHooks()
    }

    func engine() throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                         configuration: .init(bleName: "fixture-ble"), hooks: hooks, now: { [t0] in t0 })
    }

    func testAnUnconfirmedWriteThatReadsIdleNeedsACheck() async throws {
        for reply in [FakeShowerTransport.Reply.fail(.timedOut), .fail(.disconnected), .frame(Data([0xAA, 0]))] {
            reset()
            let e = try engine()
            transport.script(.frame(identity), reply)
            gateway.scriptAuthorize(.ok(auth))
            let started = try await e.start(binding)
            XCTAssertEqual(started.phase, .writePending)

            transport.script(.frame(identity))
            let s = try await e.finish(binding)
            XCTAssertEqual(s.phase, .writePending, "\(reply)")
            XCTAssertTrue(s.stateReviewRequired)
            XCTAssertEqual(s.notice, .notActive)
            XCTAssertTrue(s.canResolveManually)
            XCTAssertEqual(ShowerPage(s)?.phase, .needsCheck)
            XCTAssertEqual(try vault.showerState()?.stateReviewRequired, true, "persisted")
            XCTAssertFalse(transport.writes.contains(close))
            XCTAssertTrue(gateway.settleFrames.isEmpty)
            XCTAssertFalse(hooks.events.contains("finish.writeNeverApplied"))
        }
    }

    /// The authorization write never left (cancelled before it, or the controller refused the
    /// write): no water could run, so an idle controller ends the record without a check, also
    /// after a relaunch.
    func testAWriteThatNeverWentOutEndsWithoutACheck() async throws {
        for cause in [ShowerDeviceError.interrupted, .disconnected] {
            reset()
            let e = try engine()
            transport.script(.frame(identity), .notSent(cause))
            gateway.scriptAuthorize(.ok(auth))
            let started = try await e.start(binding)
            XCTAssertEqual(started.phase, .writePending, "\(cause)")

            let relaunched = try engine()
            transport.script(.frame(identity))
            let s = try await relaunched.finish(binding)
            XCTAssertEqual(s.phase, .idle, "\(cause)")
            XCTAssertFalse(s.stateReviewRequired)
            XCTAssertTrue(gateway.settleFrames.isEmpty)
            XCTAssertTrue(hooks.events.contains("finish.writeNeverApplied"))
        }
    }

    func testTheReducerKeepsTheDropForAProvenUnsentWriteOnly() {
        var s = ShowerReducer.reduce(.idle, .start(machineID: machine, preferredPeripheral: nil)).0
        s = ShowerReducer.reduce(s, .connected(peripheralID: "P", probe: identity)).0
        let pending = ShowerReducer.reduce(s, .authorized(auth, at: t0)).0

        let lost = ShowerReducer.reduce(pending, .writeFailed(.timedOut)).0
        let lostClosing = ShowerReducer.reduce(lost, .finish).0
        let (checked, fx) = ShowerReducer.reduce(lostClosing, .probeReplied(identity))
        XCTAssertEqual(checked.phase, .writePending)
        XCTAssertTrue(checked.stateReviewRequired)
        XCTAssertNil(checked.closingFrom)
        XCTAssertEqual(fx, [.releaseDevice])

        let unsent = ShowerReducer.reduce(pending, .cancelledBeforeSend).0
        XCTAssertEqual(unsent.phase, .writePending)
        XCTAssertTrue(unsent.authorizationNotWritten)
        XCTAssertEqual(unsent.notice, .device(.interrupted))
        let (gone, fxGone) = ShowerReducer.reduce(ShowerReducer.reduce(unsent, .finish).0, .probeReplied(identity))
        XCTAssertEqual(gone.phase, .idle)
        XCTAssertTrue(fxGone.contains(.cancelReminder))
    }
}
