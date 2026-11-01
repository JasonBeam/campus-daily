import XCTest
import Foundation
import Core
import CoreTestSupport

/// 核对宿舍的水控: only a controller that proved its identity is remembered.
final class ShowerInspectionTests: XCTestCase {
    let machine = "11223344"

    func run(_ t: FakeShowerTransport, remembered: String? = nil) async throws -> (ShowerInspection.Outcome, [String]) {
        var forgotten: [String] = []
        let outcome = try await ShowerInspection.run(transport: t, bleName: "LXT", machineID: machine,
                                                     remembered: remembered) { forgotten.append($0) }
        return (outcome, forgotten)
    }

    func testVerifiedControllerIsRemembered() async throws {
        let t = FakeShowerTransport()
        t.script(.frame(FakeFrames.identity(machine)))
        let (outcome, _) = try await run(t)
        XCTAssertEqual(outcome, .verified(peripheralID: "PERIPHERAL-A"))
        XCTAssertEqual(outcome.peripheralToRemember, "PERIPHERAL-A")
        XCTAssertEqual(t.disconnects, 1)
    }

    /// `A5` (in use) carries no identity: the check reports busy and remembers nothing.
    func testBusyControllerIsNeverRemembered() async throws {
        let t = FakeShowerTransport()
        t.script(.frame(FakeFrames.active))
        let (outcome, forgotten) = try await run(t)
        XCTAssertEqual(outcome, .busy(peripheralID: "PERIPHERAL-A"))
        XCTAssertNil(outcome.peripheralToRemember)
        XCTAssertEqual(forgotten, [])
    }

    func testRememberedControllerOfAnotherMachineIsForgottenAndRescanned() async throws {
        let t = FakeShowerTransport()
        t.scriptConnect(.success("PERIPHERAL-B"), .success("PERIPHERAL-A"))
        t.script(.frame(FakeFrames.identity("99999999")), .frame(FakeFrames.identity(machine)))
        let (outcome, forgotten) = try await run(t, remembered: "PERIPHERAL-B")
        XCTAssertEqual(forgotten, ["PERIPHERAL-B"])
        XCTAssertEqual(t.connects.map(\.preferred), ["PERIPHERAL-B", nil])
        XCTAssertEqual(outcome.peripheralToRemember, "PERIPHERAL-A")
    }

    func testOtherMachineAfterRescanIsReportedOnce() async throws {
        let t = FakeShowerTransport()
        t.script(.frame(FakeFrames.identity("99999999")))
        let (outcome, forgotten) = try await run(t)
        XCTAssertEqual(outcome, .otherMachine)
        XCTAssertEqual(forgotten, [])
        XCTAssertNil(outcome.peripheralToRemember)
    }

    func testFailedExchangeDisconnectsAndThrows() async throws {
        let t = FakeShowerTransport()
        t.script(.fail(.timedOut))
        do { _ = try await run(t); XCTFail("expected a device error") }
        catch { XCTAssertEqual(error as? ShowerDeviceError, .timedOut) }
        XCTAssertEqual(t.disconnects, 1)
        let garbled = FakeShowerTransport()
        garbled.script(.frame(Data([0x01])))
        let (outcome, _) = try await run(garbled)
        XCTAssertEqual(outcome, .unreadable)
    }

    /// A new binding saved while the old one is being checked would show that check's answer.
    func testANewBindingWaitsForTheCheckAndTheShower() {
        XCTAssertNoThrow(try ShowerBinding.checkMayReplace(mayChange: true, checking: false))
        XCTAssertThrowsError(try ShowerBinding.checkMayReplace(mayChange: true, checking: true)) {
            XCTAssertEqual($0 as? ShowerEngineError, .busy)
        }
        XCTAssertThrowsError(try ShowerBinding.checkMayReplace(mayChange: false, checking: false)) {
            XCTAssertEqual($0 as? ShowerEngineError, .blocked)
        }
        XCTAssertThrowsError(try ShowerBinding.checkMayReplace(mayChange: false, checking: true)) {
            XCTAssertEqual($0 as? ShowerEngineError, .blocked)
        }
    }
}
