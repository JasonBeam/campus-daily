import XCTest
@testable import Core
import CoreTestSupport

/// Back on the timer from the unsure face: the old 「不确定」 lock screen result goes at once
/// (no second activity beside the new 洗澡中), and the reminder counts from the return, not
/// from a water start that may be long past.
final class ShowerBackToTimerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    var running: ShowerState { ShowerState(phase: .running, machineID: "11223344", startedAt: t0) }
    var unsure: ShowerState {
        ShowerState(phase: .failed, machineID: "11223344", startedAt: t0, failure: ShowerFailure(reason: .closeUnconfirmed, needsReview: true))
    }

    func testTheReminderCountsFromTheWaterStart() {
        let start = ShowerReminderStart.next(running, after: ShowerState(phase: .authorizing), current: nil, now: t0.addingTimeInterval(5))
        XCTAssertEqual(start, t0)
        XCTAssertEqual(ShowerReminderStart.next(running, after: running, current: start, now: t0.addingTimeInterval(600)), t0)
        XCTAssertNil(ShowerReminderStart.next(unsure, after: running, current: t0, now: t0.addingTimeInterval(600)))
    }

    func testBackFromTheUnsureFaceTheReminderCountsFromNow() {
        let back = t0.addingTimeInterval(40 * 60)
        let start = ShowerReminderStart.next(running, after: unsure, current: nil, now: back)
        XCTAssertEqual(start, back)
        // It stays there while the water runs.
        XCTAssertEqual(ShowerReminderStart.next(running, after: running, current: start, now: back.addingTimeInterval(60)), back)
    }

    /// The return is saved with the record: after a relaunch (no start kept in memory) the
    /// reminder still counts from it, not from the water start 40 minutes earlier.
    func testAfterARelaunchTheReminderStillCountsFromTheReturn() async throws {
        let clock = FakeClock(t0)
        let transport = FakeShowerTransport(), gateway = FakeGateway()
        let vault = StoredShowerVault(store: InMemorySecureStore())
        let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
        gateway.scriptAuthorize(.ok(ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }),
                                                        authorizationID: "001122FF")))
        func engine() throws -> ShowerEngine {
            try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                             configuration: .init(bleName: "fixture-ble"), now: clock.function)
        }
        let e = try engine()
        transport.script(.frame(FakeFrames.identity("11223344")), .frame(FakeFrames.ack))
        _ = try await e.start(binding)
        clock.advance(40 * 60)
        transport.script(.frame(FakeFrames.active), .fail(.timedOut))
        let unsure = try await e.finish(binding)
        XCTAssertEqual(unsure.failure?.reason, .closeUnconfirmed)
        clock.advance(60)
        let back = clock.now
        transport.script(.frame(FakeFrames.active))
        let resumed = try await e.review(binding)
        XCTAssertEqual(resumed.phase, .running)

        let saved = try XCTUnwrap(try vault.showerState())
        XCTAssertEqual(saved.startedAt, t0)
        XCTAssertEqual(saved.timerResumedAt, back)
        let relaunched = try await engine().state
        XCTAssertEqual(ShowerReminderStart.next(relaunched, after: .idle, current: nil, now: back.addingTimeInterval(600)), back)
        XCTAssertEqual(AppReset.Resync(shower: relaunched, now: back).showerReminderStart, back)
    }

    func testANewTimerEndsTheEarlierResultAtOnce() {
        XCTAssertTrue(ShowerActivityAction(running, now: t0).endsEarlierResult)
        XCTAssertFalse(ShowerActivityAction(unsure, now: t0).endsEarlierResult)
        XCTAssertFalse(ShowerActivityAction(ShowerState(phase: .settling, startedAt: t0), now: t0).endsEarlierResult)
    }
}
