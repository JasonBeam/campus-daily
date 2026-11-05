import XCTest
@testable import Core
import CoreTestSupport

/// Once the controller showed a session stopped (most likely with its own button), water found
/// running later may be anyone's: 再查一次水控 keeps the check and lets go of the controller, and
/// no close or settlement goes out under the old authorization. Fakes only.
final class ShowerStoppedSessionTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "AABBCCDD")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var oldClose: Data { ShowerFrames.closeCommand(authorizationID: auth.authorizationID)! }

    var vault: StoredShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!

    override func setUp() {
        vault = StoredShowerVault(store: InMemorySecureStore())
        transport = FakeShowerTransport()
        gateway = FakeGateway()
    }

    func engine() throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                         configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
    }

    /// A shower stopped with the controller's button: 结束 finds the controller idle.
    func stopped() async throws -> ShowerEngine {
        let e = try engine()
        transport.script(.frame(FakeFrames.identity(machine)), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        _ = try await e.start(binding)
        transport.script(.frame(FakeFrames.identity(machine)))
        let s = try await e.finish(binding)
        XCTAssertTrue(s.stateReviewRequired)
        return e
    }

    func testWaterFoundRunningAfterTheControllerWentIdleIsNotOurs() async throws {
        let e = try await stopped()
        let disconnects = transport.disconnects
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        XCTAssertEqual(probed.phase, .running)
        XCTAssertTrue(probed.stateReviewRequired, "the check stands")
        XCTAssertEqual(probed.notice, .inUseByOther)
        XCTAssertEqual(transport.disconnects, disconnects + 1, "the link is let go")
        XCTAssertFalse(probed.canFinish)
        XCTAssertTrue(probed.canResolveManually)
        XCTAssertTrue(probed.canReview, "the check can still look again")
        XCTAssertEqual(ShowerRecheckResult(after: probed), .inUse)
        XCTAssertEqual(try vault.showerState()?.stateReviewRequired, true)
        XCTAssertFalse(transport.writes.contains(oldClose))
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    func testNoCloseIsSentForAStoppedSession() async throws {
        let e = try await stopped()
        let before = await e.state
        XCTAssertFalse(before.canFinish)
        do { _ = try await e.finish(binding); XCTFail("refused") }
        catch { XCTAssertEqual(error as? ShowerEngineError, .notAllowed) }
        XCTAssertFalse(transport.writes.contains(oldClose))
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }
    /// Both ways of finding the controller in use over the check put 水控有人在用 on the face;
    /// the next look that finds it stopped takes it off.
    func testTheCheckFaceSaysInUseAfterARecheckOrANextUseFoundItBusy() async throws {
        let e = try await stopped()
        var flow = ShowerPageFlow(record: await e.state, presented: true)
        XCTAssertFalse(flow.checkInUse)

        (flow, _) = ShowerPageFlow.reduce(flow, .recheckTapped)
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        (flow, _) = ShowerPageFlow.reduce(flow, .record(probed))
        (flow, _) = ShowerPageFlow.reduce(flow, .recheckReturned(try XCTUnwrap(ShowerRecheckResult(after: probed))))
        XCTAssertEqual(flow.page?.phase, .needsCheck)
        XCTAssertTrue(flow.checkInUse, "recheck found water running")

        (flow, _) = ShowerPageFlow.reduce(flow, .recheckTapped)
        XCTAssertFalse(flow.checkInUse, "a new look clears it")
        transport.script(.frame(FakeFrames.identity(machine)))
        let idle = try await e.review(binding)
        (flow, _) = ShowerPageFlow.reduce(flow, .record(idle))
        (flow, _) = ShowerPageFlow.reduce(flow, .recheckReturned(try XCTUnwrap(ShowerRecheckResult(after: idle))))
        XCTAssertFalse(flow.checkInUse)

        transport.script(.frame(FakeFrames.active))
        let busy = try await e.startNext(binding)
        (flow, _) = ShowerPageFlow.reduce(flow, .record(busy))
        XCTAssertEqual(flow.page?.phase, .needsCheck)
        XCTAssertTrue(flow.checkInUse, "the next use found it in use")

        // After a relaunch the record still waits for the controller, but the face is the check again.
        let relaunched = ShowerPageFlow(record: try XCTUnwrap(try vault.showerState()), presented: true)
        XCTAssertTrue(relaunched.record.waitingForRelease)
        XCTAssertFalse(relaunched.checkInUse)
    }
}
