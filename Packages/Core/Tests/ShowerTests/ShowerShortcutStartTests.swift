import XCTest
@testable import Core
import CoreTestSupport

/// 开始洗澡 from Siri or Shortcuts while a shower is over (stopped on the controller, or kept
/// with its outcome unknown): not turned down, it runs the page's 开始下一次洗澡
/// (`ShowerEngine.startNext`). The controller in use: nothing is sent and Siri says so. Free:
/// the old record is kept and read back, then exactly one new authorization; the old one is
/// never closed or settled. Fakes only.
final class ShowerShortcutStartTests: XCTestCase {
    let machine = "11223344"
    let oldAuthorization = "001122FF"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let next = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x40 + $0) }), authorizationID: "00112233")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Every kind of shower that is over.
    var over: [ShowerState] {
        let stopped = ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0, authorizeSent: true,
                                  authorizationID: oldAuthorization, stateReviewRequired: true)
        var kept: [ShowerState] = [stopped]
        for reason: ShowerFailureReason in [.settleUncertain, .settleRefused, .settleUnconfirmed, .closeUnconfirmed] {
            kept.append(ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: oldAuthorization,
                                    consumption: HexCoding.upper(FakeFrames.identity(machine, tail: 9)),
                                    failure: ShowerFailure(reason: reason, needsReview: true)))
        }
        return kept
    }

    func engine(over record: ShowerState) throws -> (ShowerEngine, FakeShowerTransport, FakeGateway, FlakyShowerVault) {
        let vault = FlakyShowerVault()
        try vault.saveShowerState(record)
        let transport = FakeShowerTransport(), gateway = FakeGateway()
        let e = try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                                 configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        return (e, transport, gateway, vault)
    }

    func label(_ s: ShowerState) -> String { "\(s.phase) \(String(describing: s.failure?.reason))" }

    func closeSent(_ transport: FakeShowerTransport) -> Bool {
        let close = ShowerFrames.closeCommand(authorizationID: oldAuthorization)
        return transport.writes.contains { $0 == close }
    }

    func testABusyControllerSendsNothingAndSaysSo() async throws {
        for record in over {
            XCTAssertTrue(record.showerOver, label(record))
            let (e, transport, gateway, vault) = try engine(over: record)
            transport.script(.frame(FakeFrames.active))
            let result = try await e.startOrNext(binding)
            XCTAssertEqual(gateway.authorizeFrames, [], "\(label(record)): no authorization")
            XCTAssertEqual(gateway.settleFrames, [], "\(label(record)): no settlement")
            XCTAssertFalse(closeSent(transport), "\(label(record)): no close")
            XCTAssertEqual(try vault.retainedShowers(), [], label(record))
            XCTAssertTrue(result.waitingForRelease, "\(label(record)): the page says 水控有人在用")
            XCTAssertEqual(ShowerActionOutcome.after(start: true, result, notice: nil),
                           .failure(ShowerActionFailure(ShowerAuthorText.spokenInUse)), label(record))
        }
    }

    func testAFreeControllerKeepsTheOldRecordAndAuthorizesOnce() async throws {
        for record in over {
            let (e, transport, gateway, vault) = try engine(over: record)
            transport.script(.frame(FakeFrames.identity(machine)), .frame(FakeFrames.ack))
            gateway.scriptAuthorize(.ok(next))
            let result = try await e.startOrNext(binding)
            XCTAssertEqual(result.phase, .running, label(record))
            XCTAssertEqual(result.authorizationID, next.authorizationID, label(record))
            XCTAssertEqual(gateway.authorizeFrames.count, 1, "\(label(record)): exactly one new authorization")
            XCTAssertEqual(gateway.settleFrames, [], "\(label(record)): the old one is never settled")
            XCTAssertFalse(closeSent(transport), "\(label(record)): the old one is never closed")
            XCTAssertEqual(try vault.retainedShowers(), [record.persistable], "\(label(record)): kept as it was, read back")
            XCTAssertEqual(ShowerActionOutcome.after(start: true, result, notice: nil), .success(.started), label(record))
        }
    }

    /// Nothing over: the usual start.
    func testWithNothingOverItIsTheUsualStart() async throws {
        let (e, transport, gateway, vault) = try engine(over: .idle)
        transport.script(.frame(FakeFrames.identity(machine)), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(next))
        let result = try await e.startOrNext(binding)
        XCTAssertEqual(result.phase, .running)
        XCTAssertEqual(gateway.authorizeFrames.count, 1)
        XCTAssertEqual(try vault.retainedShowers(), [])
    }

    /// The product copy for Siri, Shortcuts and the status line, from one place.
    func testTheSpokenWords() {
        XCTAssertEqual(ShowerAuthorText.spokenNoWater, "水没开。打开校日常再试一次。")
        XCTAssertEqual(ShowerAuthorText.keptStatus, "上一次洗好了，学校会自己扣费。")
        XCTAssertEqual(ShowerAuthorizeUnclearText.spoken, ShowerAuthorText.spokenNoWater)
        XCTAssertEqual(ShowerAuthorizeUnclearText.spoken(platformMessage: "余额不足"), "水没开。学校提示：余额不足。打开校日常再试一次。")
        XCTAssertEqual(ShowerActionFailure(.blocked).message, ShowerAuthorText.keptStatus)
        XCTAssertEqual(ShowerAuthorText.spokenInUse, "水控有人在用，这次没开水，也没扣钱。如果是你没停的水，先在水控上按停再试。")
        for record in over {
            XCTAssertEqual(ShowerDisplay.title(record), ShowerAuthorText.keptStatus, label(record))
        }
    }
}
