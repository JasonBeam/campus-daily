import XCTest
@testable import Core
import CoreTestSupport

/// Without a platform profile the settlement can't be sent, so 结束 (which closes the water and
/// then settles) and 再结算一次 are refused before anything reaches the controller or the
/// platform. The read-only probe still runs.
final class ShowerMissingPlatformTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

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

    func refused(_ body: () async throws -> ShowerState, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await body(); XCTFail("expected the refusal", file: file, line: line) }
        catch { XCTAssertEqual(error as? ShowerEngineError, .platformMissing, file: file, line: line) }
    }

    func testFinishIsRefusedBeforeAnythingIsSent() async throws {
        let e = try engine()
        transport.script(.frame(FakeFrames.identity(machine)), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        _ = try await e.start(binding)
        let writes = transport.writes
        let connects = transport.connects

        gateway.isAvailable = false
        await refused { try await e.finish(self.binding) }
        XCTAssertEqual(transport.writes, writes, "no probe, no close")
        XCTAssertEqual(transport.connects, connects)
        XCTAssertEqual(try vault.showerState()?.phase, .running)
        let s = await e.state
        XCTAssertEqual(s.phase, .running)
        XCTAssertTrue(s.canFinish, "finish works again once the profile is back")

        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        XCTAssertEqual(probed.phase, .running, "the read-only probe needs no platform")
    }

    func testASettleRetryIsRefusedBeforeItIsSent() async throws {
        try vault.saveShowerState(ShowerState(phase: .failed, machineID: machine, startedAt: t0,
                                              consumption: HexCoding.upper(FakeFrames.identity(machine, tail: 9)),
                                              failure: ShowerFailure(reason: .settleUncertain, needsReview: true)))
        let e = try engine()
        _ = try await e.requestSettleRetry()
        gateway.isAvailable = false
        await refused { try await e.confirmSettleRetry(self.binding) }
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        let s = await e.state
        XCTAssertEqual(s.manualSettleAttempts, 0)
        XCTAssertEqual(s.failure?.reason, .settleUncertain)
    }
}
