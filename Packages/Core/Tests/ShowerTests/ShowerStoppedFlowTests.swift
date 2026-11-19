import XCTest
@testable import Core
import CoreTestSupport

/// The author's flow: one timer page whose one button is the next step,
/// 开始洗澡 → 结束并结算 → 开始下一次洗澡. A controller found stopped at 结束 means this shower is
/// over (the school settles it): the record is kept, nothing is closed or settled, no check face,
/// and the next start goes through a read-only probe and a new authorization.
/// The page flow (`ShowerPageFlow`) is driven by the engine's records. Fakes only.
final class ShowerStoppedFlowTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "AABBCCDD")
    let next = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x40 + $0) }), authorizationID: "00112233")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
    var oldClose: Data { ShowerFrames.closeCommand(authorizationID: auth.authorizationID)! }

    var vault: FlakyShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!

    override func setUp() { fresh() }

    func fresh() {
        vault = FlakyShowerVault()
        transport = FakeShowerTransport()
        gateway = FakeGateway()
    }

    func engine() throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                         configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
    }

    /// The page as the model drives it.
    func reduce(_ flow: inout ShowerPageFlow, _ event: ShowerPageEvent) -> [ShowerPageEffect] {
        let (next, effects) = ShowerPageFlow.reduce(flow, event)
        flow = next
        return effects
    }

    /// Started, running, then 结束并结算 on a controller stopped with its own button.
    func endedOnStoppedController() async throws -> (ShowerEngine, ShowerPageFlow) {
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        var flow = ShowerPageFlow(record: .idle)
        XCTAssertEqual(reduce(&flow, .startTapped), [.start])
        _ = reduce(&flow, .record(try await e.start(binding)))
        _ = reduce(&flow, .startReturned)
        XCTAssertEqual(flow.page?.phase, .running)

        XCTAssertEqual(reduce(&flow, .endTapped), [.finish])
        transport.script(.frame(identity))
        let s = try await e.finish(binding)
        _ = reduce(&flow, .record(s))
        _ = reduce(&flow, .endNotSent(s.notice))
        _ = reduce(&flow, .endReturned)
        return (e, flow)
    }

    // MARK: 结束 on a stopped controller

    func testEndOnAStoppedControllerOffersTheNextShowerAndSendsNothing() async throws {
        let (e, flow) = try await endedOnStoppedController()
        let s = await e.state

        XCTAssertEqual(flow.page?.phase, .stopped, "the timer page's third state, not a check face")
        XCTAssertEqual(flow.page?.steps, [.future, .future, .future], "the bar back to 连接, nothing failed")
        XCTAssertTrue(flow.presented)
        XCTAssertNil(flow.endFailed, "no error line")
        XCTAssertTrue(flow.mayStartNext, "the button is 开始下一次洗澡")
        XCTAssertFalse(flow.mayEnd)
        XCTAssertFalse(flow.foundInUse)
        XCTAssertFalse(flow.showsRecheck, "no 再查一次水控 on it")
        XCTAssertTrue(flow.mayCollapse, "it doesn't block: the page can go down")

        XCTAssertEqual(transport.writes.filter { $0 == oldClose }, [], "no close")
        XCTAssertEqual(gateway.settleFrames, [], "no settlement")
        XCTAssertEqual(gateway.authorizeFrames.count, 1, "only the first shower's authorization")
        XCTAssertEqual(try vault.showerState(), s.persistable, "the record is kept")
    }

    func testTheStoppedPageCanGoDownAndComesBackAsItIs() async throws {
        var (_, flow) = try await endedOnStoppedController()
        _ = reduce(&flow, .collapseTapped)
        XCTAssertFalse(flow.presented)
        XCTAssertEqual(flow.pushedPhase, .stopped, "清爽's pushed page still shows it")
        _ = reduce(&flow, .reopen)
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(flow.page?.phase, .stopped)
    }

    func testAnEndFromTheLockScreenOnAStoppedControllerBringsThePageUp() {
        var flow = ShowerPageFlow(record: ShowerState(phase: .running, machineID: machine, startedAt: t0))
        _ = reduce(&flow, .record(ShowerState(phase: .closing, machineID: machine, startedAt: t0, closingFrom: .running)))
        _ = reduce(&flow, .record(ShowerState(phase: .running, machineID: machine, startedAt: t0, stateReviewRequired: true, notice: .notActive)))
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(flow.page?.phase, .stopped)
    }

    // MARK: 开始下一次洗澡

    func testTheNextShowerOnAnIdleControllerAuthorizesOnceAndSettlesNothing() async throws {
        var (e, flow) = try await endedOnStoppedController()
        let old = await e.state
        let settlesBefore = gateway.settleFrames.count
        let authorizesBefore = gateway.authorizeFrames.count

        XCTAssertEqual(reduce(&flow, .startNextTapped), [.startNext])
        XCTAssertTrue(flow.presented)
        XCTAssertEqual(flow.page?.phase, .connecting, "connecting at once, while the probe runs")
        XCTAssertFalse(flow.mayStartNext, "one tap")
        XCTAssertEqual(reduce(&flow, .startNextTapped), [])

        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(next))
        _ = reduce(&flow, .record(try await e.startNext(binding)))
        _ = reduce(&flow, .startNextReturned(failed: false))

        XCTAssertEqual(flow.page?.phase, .running, "the timer of the new shower")
        XCTAssertEqual(gateway.authorizeFrames.count - authorizesBefore, 1, "exactly one new authorization")
        XCTAssertEqual(gateway.settleFrames.count - settlesBefore, 0, "nothing settled for the old one")
        XCTAssertFalse(transport.writes.contains(oldClose), "the old authorization is never closed")
        XCTAssertEqual(try vault.retainedShowers(), [old.persistable], "the old record kept as it was")
        let now = await e.state
        XCTAssertEqual(now.authorizationID, next.authorizationID)
    }

    func testTheNextShowerOnABusyControllerSendsNothingAndOffersOneRecheck() async throws {
        var (e, flow) = try await endedOnStoppedController()
        let authorizesBefore = gateway.authorizeFrames.count
        let writesBefore = transport.writes.count

        _ = reduce(&flow, .startNextTapped)
        transport.script(.frame(FakeFrames.active))
        _ = reduce(&flow, .record(try await e.startNext(binding)))
        _ = reduce(&flow, .startNextReturned(failed: false))

        XCTAssertEqual(flow.page?.phase, .stopped)
        XCTAssertTrue(flow.foundInUse, "水控有人在用")
        XCTAssertFalse(flow.mayStartNext, "its one button is 再查一次")
        XCTAssertTrue(flow.showsRecheck)
        XCTAssertTrue(flow.mayRecheck)
        XCTAssertTrue(flow.mayCollapse, "and back")
        XCTAssertEqual(gateway.authorizeFrames.count, authorizesBefore, "no authorization")
        XCTAssertEqual(gateway.settleFrames, [])
        XCTAssertEqual(Array(transport.writes.dropFirst(writesBefore)), [ShowerFrames.probeCommand], "the read-only probe only")
        XCTAssertEqual(try vault.retainedShowers(), [], "nothing kept yet: nothing went ahead")

        // Relaunched while it waits: still 水控有人在用.
        let relaunched = ShowerPageFlow(record: ShowerReducer.restore(try vault.showerState()), presented: true)
        XCTAssertTrue(relaunched.foundInUse)

        // 再查一次: still running → stays; stopped now → back to 开始下一次洗澡.
        XCTAssertEqual(reduce(&flow, .recheckTapped), [.recheck])
        transport.script(.frame(FakeFrames.active))
        let still = try await e.review(binding)
        _ = reduce(&flow, .record(still))
        _ = reduce(&flow, .recheckReturned(ShowerRecheckResult(after: still)))
        XCTAssertTrue(flow.foundInUse)
        XCTAssertFalse(flow.mayStartNext)

        _ = reduce(&flow, .recheckTapped)
        transport.script(.frame(identity))
        let free = try await e.review(binding)
        _ = reduce(&flow, .record(free))
        _ = reduce(&flow, .recheckReturned(ShowerRecheckResult(after: free)))
        XCTAssertFalse(flow.foundInUse)
        XCTAssertTrue(flow.mayStartNext)
        XCTAssertFalse(free.waitingForRelease, "seen free again")
        XCTAssertEqual(gateway.authorizeFrames.count, authorizesBefore, "rechecks are read-only")
        XCTAssertEqual(gateway.settleFrames, [])
        XCTAssertFalse(transport.writes.contains(oldClose))
    }

    func testANextShowerThatCannotKeepTheRecordSendsNothing() async throws {
        for keepFails in [true, false] {
            fresh()
            var (e, flow) = try await endedOnStoppedController()
            let old = await e.state
            let authorizesBefore = gateway.authorizeFrames.count
            vault.failRetain = keepFails
            vault.failSave = !keepFails
            _ = reduce(&flow, .startNextTapped)
            transport.script(.frame(identity), .frame(FakeFrames.ack))
            gateway.scriptAuthorize(.ok(next))
            do { _ = try await e.startNext(binding); XCTFail("storage error") }
            catch { XCTAssertEqual(error as? ShowerEngineError, .storage) }
            _ = reduce(&flow, .record(await e.state))
            _ = reduce(&flow, .startNextReturned(failed: true))

            XCTAssertEqual(gateway.authorizeFrames.count, authorizesBefore, "no new authorization")
            XCTAssertEqual(gateway.settleFrames, [])
            XCTAssertFalse(transport.writes.contains(oldClose))
            XCTAssertEqual(flow.page?.phase, .stopped, "back on the stopped page")
            XCTAssertTrue(flow.nextFailed, "with a line saying it didn't go")
            vault.failSave = false
            XCTAssertEqual(try vault.showerState(), old.persistable, "the old record stays in place")
        }
    }

    // MARK: After 55

    func testWaterFoundRunningAfterTheStopNeverResumesOrEndsTheOldShower() async throws {
        var (e, flow) = try await endedOnStoppedController()
        transport.script(.frame(FakeFrames.active))
        let probed = try await e.review(binding)
        _ = reduce(&flow, .record(probed))

        XCTAssertEqual(flow.page?.phase, .stopped, "not back on the timer")
        XCTAssertFalse(probed.canFinish)
        XCTAssertFalse(flow.mayEnd)
        XCTAssertEqual(reduce(&flow, .endTapped), [])
        do { _ = try await e.finish(binding); XCTFail("refused") }
        catch { XCTAssertEqual(error as? ShowerEngineError, .notAllowed) }
        XCTAssertFalse(transport.writes.contains(oldClose), "never closed with the old authorization")
        XCTAssertEqual(gateway.settleFrames, [], "never settled")
        let relaunched = ShowerReducer.restore(try vault.showerState())
        XCTAssertEqual(ShowerPage(relaunched)?.phase, .stopped)
        XCTAssertFalse(relaunched.canFinish)
    }

    // MARK: Routes

    /// While a shower is on (connecting, water, stopped, settling), every way to 热水 opens the
    /// timer page of the theme (暖橙's cover, 清爽's pushed page), not the 热水洗澡 screen.
    func testEveryRouteToHotWaterOpensTheTimerPageWhileAShowerIsOn() {
        let on: [ShowerState] = [
            ShowerState(phase: .authorizing, machineID: machine),
            ShowerState(phase: .writePending, machineID: machine, startedAt: t0),
            ShowerState(phase: .running, machineID: machine, startedAt: t0),
            ShowerState(phase: .running, machineID: machine, startedAt: t0, stateReviewRequired: true),
            ShowerState(phase: .closing, machineID: machine, startedAt: t0, closingFrom: .running),
            ShowerState(phase: .settling, machineID: machine, startedAt: t0),
            // Kept for the school like a stopped shower.
            ShowerState(phase: .failed, machineID: machine, failure: ShowerFailure(reason: .settleUncertain, needsReview: true)),
        ]
        for record in on {
            let flow = ShowerPageFlow(record: record)
            XCTAssertTrue(flow.opensPageOnRoute, "\(record.phase)")
            XCTAssertNotNil(flow.pushedPhase, "清爽's page shows it: \(record.phase)")
            var opened = flow
            _ = reduce(&opened, .reopen)
            XCTAssertTrue(opened.presented, "\(record.phase)")
        }
        let off: [ShowerState] = [
            .idle,
            ShowerState(phase: .done, machineID: machine, receipt: ShowerReceipt(amount: Money(fen: 42))),
            ShowerState(phase: .failed, machineID: machine, failure: ShowerFailure(reason: .deviceUnavailable, needsReview: false)),
        ]
        for record in off {
            XCTAssertFalse(ShowerPageFlow(record: record).opensPageOnRoute, "\(record.phase)")
        }
    }

    // MARK: Lock screen and reminder

    /// Stopped on the controller, the shower is over: no 洗澡中 left on the lock screen (its 结束
    /// would only be refused) and no 「还在计时」 reminder.
    func testAStoppedShowerLeavesNoLiveActivityOrReminder() {
        let running = ShowerState(phase: .running, machineID: machine, startedAt: t0)
        let stopped = ShowerState(phase: .running, machineID: machine, startedAt: t0, stateReviewRequired: true)
        let busy = ShowerState(phase: .running, machineID: machine, startedAt: t0, stateReviewRequired: true, waitingForRelease: true)
        for record in [stopped, busy] {
            XCTAssertEqual(ShowerActivityAction(record, now: t0), .end)
            XCTAssertNil(ShowerReminderStart.next(record, after: running, current: t0, now: t0))
        }
        XCTAssertEqual(ShowerActivityAction(running, now: t0), .show(startedAt: t0, writeUnconfirmed: false))
        XCTAssertEqual(ShowerReminderStart.next(running, after: running, current: t0, now: t0), t0)
    }
}
