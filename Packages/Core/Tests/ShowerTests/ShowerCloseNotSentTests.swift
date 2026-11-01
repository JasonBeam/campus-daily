import XCTest
@testable import Core
import CoreTestSupport

/// 结束 whose close never reached the controller goes back to the timer, so it can be sent
/// again; only a close lost after the controller took the write needs a check. From that check
/// a read-only probe that finds water running goes back to the timer too.
final class ShowerCloseNotSentTests: XCTestCase {
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

    func closeUnconfirmed() async throws -> ShowerEngine {
        let e = try await running()
        transport.script(.frame(FakeFrames.active), .fail(.timedOut))
        let s = try await e.finish(binding)
        XCTAssertEqual(s.failure?.reason, .closeUnconfirmed)
        return e
    }

    // MARK: Not sent

    func testACloseThatNeverReachedTheControllerGoesBackToTheTimer() async throws {
        for cause in [ShowerDeviceError.interrupted, .disconnected] {
            reset()
            let e = try await running()
            transport.script(.frame(FakeFrames.active), .notSent(cause))
            let back = try await e.finish(binding)
            XCTAssertEqual(back.phase, .running, "\(cause)")
            XCTAssertNil(back.failure)
            XCTAssertFalse(back.closeSent)
            XCTAssertEqual(ShowerEndFailure(back.notice), .notSent)
            XCTAssertEqual(try vault.showerState()?.phase, .running, "persisted")
            XCTAssertTrue(back.canFinish)

            transport.script(.frame(FakeFrames.active), .frame(consumption))
            gateway.scriptSettle(.ok(receipt))
            let done = try await e.finish(binding)
            XCTAssertEqual(done.phase, .done)
            XCTAssertEqual(transport.writes.filter { $0 == close }.count, 2, "the close went out again")
        }
    }

    /// The write went out and then the answer was lost: the controller may have closed.
    func testACloseLostAfterTheWriteNeedsACheck() async throws {
        for failure in [ShowerDeviceError.timedOut, .disconnected, .interrupted] {
            reset()
            let e = try await running()
            transport.script(.frame(FakeFrames.active), .fail(failure))
            let s = try await e.finish(binding)
            XCTAssertEqual(s.failure?.reason, .closeUnconfirmed, "\(failure)")
            XCTAssertEqual(s.failure?.needsReview, true)
        }
    }

    // MARK: Probe from an unconfirmed close

    func testAProbeThatFindsWaterRunningAllowsTheCloseAgain() async throws {
        let e = try await closeUnconfirmed()
        transport.script(.frame(FakeFrames.active))
        let s = try await e.review(binding)
        XCTAssertEqual(s.phase, .running)
        XCTAssertNil(s.failure)
        XCTAssertFalse(s.closeSent)
        XCTAssertFalse(s.stateReviewRequired)
        XCTAssertTrue(s.canFinish)
        XCTAssertEqual(try vault.showerState()?.phase, .running)
        XCTAssertNil(ShowerRecheckResult(after: s), "back on the timer")

        // The close goes out again; what it returns waits for the user's settle.
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let held = try await e.finish(binding)
        XCTAssertEqual(transport.writes.filter { $0 == close }.count, 2)
        XCTAssertEqual(held.phase, .failed)
        XCTAssertTrue(held.canRetrySettle)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    func testAProbeThatFindsTheControllerStoppedKeepsTheCheck() async throws {
        let e = try await closeUnconfirmed()
        let before = transport.writes.count
        transport.script(.frame(identity))
        let stopped = try await e.review(binding)
        XCTAssertEqual(stopped.failure?.reason, .closeUnconfirmed)
        XCTAssertEqual(ShowerRecheckResult(after: stopped), .stopped)
        XCTAssertTrue(stopped.canResolveManually)

        transport.scriptConnect(.failure(.notFound))
        let unreachable = try await e.review(binding)
        XCTAssertEqual(unreachable.failure?.reason, .closeUnconfirmed)
        XCTAssertEqual(ShowerRecheckResult(after: unreachable), .noConnection)

        transport.script(.frame(FakeFrames.identity("99999999")))
        let other = try await e.review(binding)
        XCTAssertEqual(ShowerRecheckResult(after: other), .otherController)

        // Read-only: every write after the unconfirmed close is the identity probe.
        let later = transport.writes.dropFirst(before)
        XCTAssertEqual(later.count, 2, "one probe per reachable controller")
        XCTAssertTrue(later.allSatisfy { $0 == ShowerFrames.probeCommand })
        XCTAssertEqual(transport.connects.suffix(3).map(\.required), Array(repeating: "PERIPHERAL-A", count: 3),
                       "only the session's controller")
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    func testOnlyAnUnconfirmedCloseCanBeProbedFromAFailure() {
        func failed(_ reason: ShowerFailureReason) -> ShowerState {
            ShowerState(phase: .failed, machineID: machine, peripheralID: "P", failure: ShowerFailure(reason: reason, needsReview: true))
        }
        XCTAssertTrue(failed(.closeUnconfirmed).canReview)
        let (probing, fx) = ShowerReducer.reduce(failed(.closeUnconfirmed), .review)
        XCTAssertTrue(probing.reviewing)
        XCTAssertFalse(probing.canReview, "one probe at a time")
        XCTAssertEqual(fx, [.probe(peripheralID: "P")])
        for reason in [ShowerFailureReason.settleUncertain, .settleRefused, .settleUnconfirmed, .authorizeUncertain, .authorizationInvalid] {
            XCTAssertFalse(failed(reason).canReview, reason.rawValue)
            XCTAssertEqual(ShowerReducer.reduce(failed(reason), .review).1, [], reason.rawValue)
        }
    }

    // MARK: Page

    func testTheUnsureFaceOfAnUnconfirmedCloseOffersTheProbe() {
        let unsure = ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0,
                                 failure: ShowerFailure(reason: .closeUnconfirmed, needsReview: true))
        var flow = ShowerPageFlow(record: unsure, presented: true)
        XCTAssertEqual(flow.page?.phase, .unsure)
        XCTAssertTrue(flow.mayRecheck)
        XCTAssertEqual(ShowerPageFlow.reduce(flow, .recheckTapped).1, [.recheck])
        flow = ShowerPageFlow.reduce(flow, .recheckTapped).0

        var stopped = flow
        var after = unsure
        after.notice = .notActive
        stopped = ShowerPageFlow.reduce(stopped, .record(after)).0
        stopped = ShowerPageFlow.reduce(stopped, .recheckReturned(ShowerRecheckResult(after: after))).0
        XCTAssertEqual(stopped.recheckResult, .stopped)
        XCTAssertEqual(stopped.page?.phase, .unsure)

        flow = ShowerPageFlow.reduce(flow, .record(ShowerState(phase: .running, machineID: machine, startedAt: t0))).0
        flow = ShowerPageFlow.reduce(flow, .recheckReturned(nil)).0
        XCTAssertEqual(flow.page?.phase, .running)
        XCTAssertTrue(flow.presented)
        XCTAssertTrue(flow.mayEnd)

        let settle = ShowerState(phase: .failed, machineID: machine, startedAt: t0,
                                 failure: ShowerFailure(reason: .settleUncertain, needsReview: true))
        XCTAssertFalse(ShowerPageFlow(record: settle, presented: true).mayRecheck)
    }
}
