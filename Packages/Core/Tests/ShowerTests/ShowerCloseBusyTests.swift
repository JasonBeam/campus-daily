import XCTest
@testable import Core
import CoreTestSupport

/// The controller answered the close with `A5` (still busy, no consumption): the close went out
/// and the record waits for the user's check. Nothing ever sends the close again for it, not a
/// check that finds water running, not a relaunch; 开始下一次洗澡 still verifies the controller
/// idle before it keeps the record aside and asks for a new authorization.
final class ShowerCloseBusyTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let next = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x40 + $0) }), authorizationID: "00AABBCC")
    let receipt = ShowerReceipt(amount: Money(fen: 163))
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
    var consumption: Data { FakeFrames.identity(machine, tail: 9) }
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

    var closes: Int { transport.writes.filter { $0 == close }.count }

    func closeBusy() async throws -> ShowerEngine {
        let e = try await running()
        transport.script(.frame(FakeFrames.active), .frame(FakeFrames.active))
        let s = try await e.finish(binding)
        XCTAssertEqual(s.failure?.reason, .closeBusy)
        return e
    }

    func testA5ToTheCloseIsCloseBusyAndKept() async throws {
        let e = try await running()
        transport.script(.frame(FakeFrames.active), .frame(FakeFrames.active))
        gateway.scriptSettle(.ok(receipt))
        let s = try await e.finish(binding)
        XCTAssertEqual(s.phase, .failed)
        XCTAssertEqual(s.failure?.reason, .closeBusy)
        XCTAssertEqual(s.failure?.needsReview, true)
        XCTAssertFalse(ShowerFailureReason.closeBusy.isBeforeWater)
        XCTAssertTrue(s.closeSent)
        XCTAssertNil(s.consumption)
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertFalse(s.canFinish)
        XCTAssertFalse(s.canStart)
        XCTAssertFalse(s.canRetrySettle)
        XCTAssertTrue(s.showerOver)
        XCTAssertTrue(s.canStartNext)
        XCTAssertTrue(s.canReview, "a read-only check may still look")
        XCTAssertEqual(ShowerPage(s)?.phase, .stopped)
        XCTAssertEqual(ShowerPage(s)?.closeBusy, true)
        XCTAssertEqual(try vault.showerState()?.failure?.reason, .closeBusy, "persisted")
        XCTAssertEqual(ShowerReducer.reduce(s, .finish).1, [], "the reducer sends no close either")
    }

    /// The suggested end-to-end path: AC → A5, checks that find water running and then idle,
    /// a relaunch, 结束 asked again from every entry. One close in all, no settlement, the
    /// record as it was.
    func testReviewFindingWaterNeverReopensTheClose() async throws {
        let e = try await closeBusy()
        let kept = await e.state

        for _ in 0..<3 {
            transport.script(.frame(FakeFrames.active))
            let s = try await e.review(binding)
            XCTAssertEqual(s.phase, .failed)
            XCTAssertEqual(s.failure?.reason, .closeBusy)
            XCTAssertEqual(s.notice, .inUseByOther)
            XCTAssertFalse(s.canFinish)
            XCTAssertNil(s.timerResumedAt)
            await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        }
        transport.script(.frame(identity))
        let stopped = try await e.review(binding)
        XCTAssertEqual(stopped.failure?.reason, .closeBusy)
        XCTAssertEqual(stopped.notice, .notActive)
        XCTAssertFalse(stopped.canFinish)

        let relaunched = try engine()
        let restored = await relaunched.state
        XCTAssertEqual(restored.persistable, kept.persistable, "the record as it was")
        await XCTAssertThrowsErrorAsync(try await relaunched.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        transport.script(.frame(FakeFrames.active))
        _ = try await relaunched.review(binding)
        await XCTAssertThrowsErrorAsync(try await relaunched.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }

        XCTAssertEqual(closes, 1)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertEqual(try vault.showerState()?.persistable, kept.persistable)
    }

    /// The same for a close whose answer was lost or came back unreadable.
    func testSameForAnUnconfirmedClose() async throws {
        for second in [FakeShowerTransport.Reply.fail(.timedOut), .frame(FakeFrames.identity("99999999", tail: 9))] {
            reset()
            let e = try await running()
            transport.script(.frame(FakeFrames.active), second)
            let unsure = try await e.finish(binding)
            XCTAssertEqual(unsure.failure?.reason, .closeUnconfirmed)

            transport.script(.frame(FakeFrames.active))
            let s = try await e.review(binding)
            XCTAssertEqual(s.phase, .failed)
            XCTAssertEqual(s.failure?.reason, .closeUnconfirmed)
            XCTAssertEqual(s.notice, .inUseByOther)
            XCTAssertFalse(s.canFinish)
            XCTAssertEqual(ShowerPageFlow(record: s, presented: true).page?.phase, .stopped)
            XCTAssertFalse(ShowerPageFlow(record: s, presented: true).mayEnd)
            await XCTAssertThrowsErrorAsync(try await e.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
            XCTAssertEqual(closes, 1)
            XCTAssertTrue(gateway.settleFrames.isEmpty)
        }
    }

    func testRelaunchKeepsItClosed() async throws {
        _ = try await closeBusy()
        for _ in 0..<2 {
            let relaunched = try engine()
            let s = await relaunched.state
            XCTAssertEqual(s.failure?.reason, .closeBusy)
            XCTAssertFalse(s.canFinish)
            XCTAssertEqual(ShowerReducer.restore(s).failure?.reason, .closeBusy)
            await XCTAssertThrowsErrorAsync(try await relaunched.finish(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        }
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    /// 开始下一次洗澡 over it: water still running lets the link go and sends nothing; once idle
    /// with this machine's identity, the record is kept aside and only then a new authorization
    /// goes out. The old record is never closed or settled.
    func testTheNextUseStillVerifiesTheControllerIdleFirst() async throws {
        let e = try await closeBusy()
        let kept = await e.state
        let authorizes = gateway.authorizeFrames.count

        transport.script(.frame(FakeFrames.active))
        let waiting = try await e.startNext(binding)
        XCTAssertTrue(waiting.waitingForRelease)
        XCTAssertEqual(gateway.authorizeFrames.count, authorizes, "nothing authorized while in use")

        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(next))
        let fresh = try await e.startNext(binding)
        XCTAssertEqual(fresh.phase, .running)
        XCTAssertEqual(fresh.authorizationID, "00AABBCC")
        XCTAssertEqual(gateway.authorizeFrames.count, authorizes + 1)
        let retained = try vault.retainedShowers()
        XCTAssertEqual(retained.last?.failure?.reason, .closeBusy)
        XCTAssertEqual(retained.last?.authorizationID, kept.authorizationID)
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    /// What the record says where the page is not shown (the lock screen, Siri, the status).
    func testItsWords() {
        let s = ShowerState(phase: .failed, machineID: machine, startedAt: t0, authorizationID: "001122FF", closeSent: true,
                            failure: ShowerFailure(reason: .closeBusy, needsReview: true))
        XCTAssertEqual(ShowerDisplay.title(s), "水控还没停，在水控上按停。学校会自己扣费。")
        XCTAssertEqual(ShowerAuthorText.closeBusyStatus, "水控还没停，在水控上按停。学校会自己扣费。")
        XCTAssertEqual(ShowerActionOutcome.after(start: false, s, notice: nil),
                       .failure(ShowerActionFailure("水控还没停，在水控上按停。学校会自己扣费。")), "what Siri says after 结束")
        XCTAssertEqual(ShowerActivityAction(s, now: t0), .unconfirmed(startedAt: t0, dismissAfter: ShowerActivityAction.unconfirmedDismissal))
        XCTAssertFalse(ShowerActivityAction(s, now: t0).endsEarlierResult)
    }
}
