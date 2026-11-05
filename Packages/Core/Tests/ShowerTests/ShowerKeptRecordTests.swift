import XCTest
@testable import Core
import CoreTestSupport

/// A record whose outcome is unknown (needsReview: a settlement or close without an answer, an
/// unclear authorization) gets no resolve flow: it is kept like a shower
/// stopped on the controller, the school settles it, and the app never settles it again. The
/// timer page shows it as the stopped page (「上一次洗好了」, 开始下一次洗澡, the one line);
/// home says 「去洗澡」. Fakes only.
final class ShowerKeptRecordTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let next = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x40 + $0) }), authorizationID: "00112233")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let consumption = HexCoding.upper(FakeFrames.identity("11223344", tail: 9))

    static let reviewReasons: [ShowerFailureReason] = [.settleRefused, .settleUncertain, .settleUnconfirmed, .closeUnconfirmed,
                                                       .authorizeUncertain, .authorizationInvalid]

    func unsure(_ reason: ShowerFailureReason) -> ShowerState {
        // An unclear authorize never started the water: no start time (as the reducer leaves it).
        ShowerState(phase: .failed, machineID: machine, startedAt: reason.isUnclearAuthorize ? nil : t0, consumption: consumption,
                    failure: ShowerFailure(reason: reason, needsReview: true))
    }

    func reduce(_ flow: inout ShowerPageFlow, _ event: ShowerPageEvent) -> [ShowerPageEffect] {
        let (next, effects) = ShowerPageFlow.reduce(flow, event)
        flow = next
        return effects
    }

    // MARK: The page

    func testAnUnsureRecordIsTheStoppedPage() {
        for reason in Self.reviewReasons {
            let record = unsure(reason)
            var flow = ShowerPageFlow(record: record, presented: true)
            XCTAssertEqual(flow.page?.phase, .stopped, "\(reason.rawValue): no 不确定 face")
            XCTAssertEqual(flow.page?.steps, [.future, .future, .future], reason.rawValue)
            XCTAssertTrue(record.showerOver, reason.rawValue)
            XCTAssertTrue(flow.mayStartNext, "\(reason.rawValue): its one button is 开始下一次洗澡")
            XCTAssertFalse(flow.showsRecheck, "\(reason.rawValue): no 再查一次水控")
            XCTAssertFalse(flow.mayRecheck, reason.rawValue)
            XCTAssertTrue(flow.mayCollapse, "\(reason.rawValue): it doesn't block")
            XCTAssertTrue(flow.opensPageOnRoute, "\(reason.rawValue): 热水 opens the timer page")
            _ = reduce(&flow, .collapseTapped)
            XCTAssertFalse(flow.presented, reason.rawValue)
        }
    }

    func testAHarmlessFailureIsNotKept() {
        let harmless = ShowerState(phase: .failed, machineID: machine, failure: ShowerFailure(reason: .deviceUnavailable, needsReview: false))
        XCTAssertFalse(harmless.showerOver)
        XCTAssertNotEqual(ShowerPageFlow(record: harmless).page?.phase, .stopped)
        XCTAssertFalse(ShowerState(phase: .running, machineID: machine, startedAt: t0).showerOver)
        XCTAssertTrue(ShowerState(phase: .running, machineID: machine, startedAt: t0, stateReviewRequired: true).showerOver)
    }

    // MARK: The next shower over it

    func engine(over record: ShowerState) throws -> (ShowerEngine, FakeShowerTransport, FakeGateway, FlakyShowerVault) {
        let vault = FlakyShowerVault()
        try vault.saveShowerState(record)
        let transport = FakeShowerTransport(), gateway = FakeGateway()
        let e = try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                                 configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        return (e, transport, gateway, vault)
    }

    func testTheNextShowerOverAnUnsureRecordAuthorizesOnceAndSettlesNothing() async throws {
        for reason in Self.reviewReasons {
            let record = unsure(reason)
            let (e, transport, gateway, vault) = try engine(over: record)
            var flow = ShowerPageFlow(record: await e.state, presented: true)
            XCTAssertEqual(reduce(&flow, .startNextTapped), [.startNext], reason.rawValue)
            transport.script(.frame(FakeFrames.identity(machine)), .frame(FakeFrames.ack))
            gateway.scriptAuthorize(.ok(next))
            _ = reduce(&flow, .record(try await e.startNext(binding)))
            _ = reduce(&flow, .startNextReturned(failed: false))
            XCTAssertEqual(flow.page?.phase, .running, reason.rawValue)
            XCTAssertEqual(gateway.authorizeFrames.count, 1, "\(reason.rawValue): one new authorization")
            XCTAssertEqual(gateway.settleFrames, [], "\(reason.rawValue): never settled again")
            XCTAssertEqual(try vault.retainedShowers(), [record.persistable], "\(reason.rawValue): kept as it was")
        }
    }

    func testABusyControllerOverAnUnsureRecordSendsNothingAndOffersOneRecheck() async throws {
        let record = unsure(.settleUncertain)
        let (e, transport, gateway, vault) = try engine(over: record)
        var flow = ShowerPageFlow(record: await e.state, presented: true)
        _ = reduce(&flow, .startNextTapped)
        transport.script(.frame(FakeFrames.active))
        _ = reduce(&flow, .record(try await e.startNext(binding)))
        _ = reduce(&flow, .startNextReturned(failed: false))

        XCTAssertEqual(flow.page?.phase, .stopped)
        XCTAssertTrue(flow.foundInUse, "水控有人在用")
        XCTAssertFalse(flow.mayStartNext)
        XCTAssertTrue(flow.showsRecheck)
        XCTAssertTrue(flow.mayRecheck, "its one button 再查一次")
        XCTAssertEqual(gateway.authorizeFrames, [])
        XCTAssertEqual(gateway.settleFrames, [])
        XCTAssertEqual(try vault.retainedShowers(), [])

        // 再查一次: a read-only probe. Still in use: stays; stopped: 开始下一次洗澡 again.
        XCTAssertEqual(reduce(&flow, .recheckTapped), [.recheck])
        transport.script(.frame(FakeFrames.active))
        _ = reduce(&flow, .record(try await e.review(binding)))
        _ = reduce(&flow, .recheckReturned(ShowerRecheckResult(after: await e.state)))
        XCTAssertTrue(flow.foundInUse)

        XCTAssertEqual(reduce(&flow, .recheckTapped), [.recheck])
        transport.script(.frame(FakeFrames.identity(machine)))
        _ = reduce(&flow, .record(try await e.review(binding)))
        _ = reduce(&flow, .recheckReturned(ShowerRecheckResult(after: await e.state)))
        XCTAssertFalse(flow.foundInUse)
        XCTAssertTrue(flow.mayStartNext)
        XCTAssertEqual(flow.page?.phase, .stopped)
        XCTAssertEqual(gateway.authorizeFrames, [])
        XCTAssertEqual(gateway.settleFrames, [], "a probe never settles")
        let now = await e.state
        XCTAssertEqual(now.phase, .failed, "the record stays as it was")
        XCTAssertEqual(now.failure?.reason, .settleUncertain)
    }

    // MARK: Home and copy

    func testHomeSaysGoShower() {
        let tile = ShowerTileStatus.of(.stopped, signedIn: true, lastMinutes: 11, lastCost: 1.32, issue: nil)
        XCTAssertEqual(tile.text, "去洗澡")
        XCTAssertEqual(tile.spoken, "去洗澡，上一次洗好了")
        XCTAssertEqual(tile.tone, .secondary, "not a warning")
    }

    /// The product copy, from one place.
    func testTheWords() {
        XCTAssertEqual(ShowerAuthorText.stoppedTitle, "上一次洗好了")
        XCTAssertEqual(ShowerAuthorText.stoppedNote, "在水控上按停就算洗完了，学校会自己扣费，可以在学校的热水记录里看。")
        XCTAssertEqual(ShowerAuthorText.startNext, "开始下一次洗澡")
        XCTAssertEqual(ShowerAuthorText.homeButton, "去洗澡")
        XCTAssertEqual(ShowerAuthorText.homeButtonLabel, "去洗澡，上一次洗好了")
    }
}
