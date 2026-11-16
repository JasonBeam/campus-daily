import XCTest
@testable import Core
import CoreTestSupport

/// The automatic check while the app is in front: only over a record whose water may run and
/// that waits for nothing, at most once per interval, and only the read-only `AA` probe.
final class ShowerAutoReviewTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
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

    // MARK: Which records

    func testOnlyWhileWaterMayRunAndUnreviewed() {
        for phase in ShowerPhase.allCases {
            for flags in 0..<(1 << 5) {
                let s = ShowerState(phase: phase, machineID: machine, startedAt: t0, authorizationID: "001122FF",
                                    stateReviewRequired: flags & 1 != 0, reviewing: flags & 2 != 0,
                                    authorizationNotWritten: flags & 4 != 0, holdSettle: flags & 16 != 0,
                                    waitingForRelease: flags & 8 != 0)
                let unflagged = flags & 0b1111 == 0
                let expected = (phase == .running || phase == .writePending) && unflagged
                XCTAssertEqual(ShowerAutoReview.eligible(s), expected, "\(phase) \(flags)")
            }
        }
    }

    func testNeverOverAnUnconfirmedOrBusyClose() {
        for reason in [ShowerFailureReason.closeUnconfirmed, .closeBusy, .settleUncertain, .settleUnconfirmed, .authorizeUncertain] {
            var s = ShowerState(phase: .failed, machineID: machine, startedAt: t0, authorizationID: "001122FF", closeSent: true,
                                failure: ShowerFailure(reason: reason, needsReview: true))
            XCTAssertFalse(ShowerAutoReview.eligible(s), reason.rawValue)
            s.waitingForRelease = true
            XCTAssertFalse(ShowerAutoReview.eligible(s), reason.rawValue)
        }
    }

    func testThrottle() {
        XCTAssertEqual(ShowerAutoReview.interval, 30)
        XCTAssertEqual(ShowerAutoReview.tick, .seconds(5))
        XCTAssertTrue(ShowerAutoReview.due(lastAttempt: nil, now: t0))
        XCTAssertFalse(ShowerAutoReview.due(lastAttempt: t0, now: t0))
        XCTAssertFalse(ShowerAutoReview.due(lastAttempt: t0, now: t0.addingTimeInterval(29.9)))
        XCTAssertTrue(ShowerAutoReview.due(lastAttempt: t0, now: t0.addingTimeInterval(30)))
        // A clock set back does not hold the check off forever, nor make it run every tick.
        XCTAssertFalse(ShowerAutoReview.due(lastAttempt: t0, now: t0.addingTimeInterval(-5)))
        XCTAssertTrue(ShowerAutoReview.due(lastAttempt: t0, now: t0.addingTimeInterval(-31)))
    }

    // MARK: What it sends

    /// Water still running (`A5`): only `AA` went out, the link is kept as the manual check
    /// keeps it, and nothing reached the platform.
    func testAutoReviewSendsOnlyProbe() async throws {
        let e = try await running()
        let writes = transport.writes.count, disconnects = transport.disconnects
        let authorizes = gateway.authorizeFrames.count
        transport.script(.frame(FakeFrames.active))
        let s = try await e.autoReview(binding)
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(Array(transport.writes.dropFirst(writes)), [ShowerFrames.probeCommand])
        XCTAssertEqual(transport.disconnects, disconnects, "A5 keeps the connection")
        XCTAssertEqual(gateway.authorizeFrames.count, authorizes)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertFalse(transport.writes.contains(close))
    }

    /// Stopped on the controller: the record is over (as the manual check leaves it), the link
    /// is let go, and still only `AA` went out.
    func testAutoReviewFindingTheControllerStoppedEndsNothingByItself() async throws {
        let e = try await running()
        let writes = transport.writes.count, disconnects = transport.disconnects
        transport.script(.frame(identity))
        let s = try await e.autoReview(binding)
        XCTAssertEqual(s.phase, .running)
        XCTAssertTrue(s.stateReviewRequired)
        XCTAssertEqual(ShowerPage(s)?.phase, .stopped)
        XCTAssertEqual(Array(transport.writes.dropFirst(writes)), [ShowerFrames.probeCommand])
        XCTAssertEqual(transport.disconnects, disconnects + 1)
        XCTAssertTrue(gateway.settleFrames.isEmpty)

        // Over now: no further automatic check.
        await XCTAssertThrowsErrorAsync(try await e.autoReview(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        XCTAssertEqual(transport.writes.count, writes + 1)
    }

    /// The engine itself refuses a record the rule leaves out, whatever the caller saw.
    func testTheEngineRefusesAnIneligibleRecord() async throws {
        let records = [
            ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF", closeSent: true,
                        failure: ShowerFailure(reason: .closeUnconfirmed, needsReview: true)),
            ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF", closeSent: true,
                        failure: ShowerFailure(reason: .closeBusy, needsReview: true)),
            ShowerState(phase: .writePending, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                        authorizationNotWritten: true),
            ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                        stateReviewRequired: true, waitingForRelease: true),
            ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                        stateReviewRequired: true),
        ]
        for record in records {
            reset()
            try vault.saveShowerState(record)
            let e = try engine()
            transport.script(.frame(FakeFrames.active))
            await XCTAssertThrowsErrorAsync(try await e.autoReview(binding)) {
                XCTAssertEqual($0 as? ShowerEngineError, .notAllowed, "\(record.phase) \(String(describing: record.failure?.reason))")
            }
            XCTAssertTrue(transport.writes.isEmpty)
            XCTAssertTrue(transport.connects.isEmpty)
        }
    }

    /// A failed probe leaves the record as it was; the caller decides when to try again.
    func testAFailedProbeChangesNothing() async throws {
        let e = try await running()
        transport.scriptConnect(.failure(.notFound))
        let s = try await e.autoReview(binding)
        XCTAssertEqual(s.phase, .running)
        XCTAssertFalse(s.stateReviewRequired)
        XCTAssertEqual(s.notice, .device(.notFound))
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }
}

func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line,
                                  _ handler: (Error) -> Void = { _ in }) async {
    do {
        _ = try await expression()
        XCTFail("no error thrown", file: file, line: line)
    } catch {
        handler(error)
    }
}
