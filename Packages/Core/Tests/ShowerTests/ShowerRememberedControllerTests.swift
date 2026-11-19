import XCTest
import Foundation
import Core
import CoreTestSupport

/// The remembered controller survives failed connects and wrong devices, so the next start can
/// go straight to it instead of scanning again.
extension ShowerEngineTests {
    func testFailedConnectKeepsTheRememberedController() async throws {
        try vault.saveBinding(binding)
        try vault.saveShowerState(ShowerState(phase: .idle, machineID: machine, peripheralID: "PERIPHERAL-B"))
        let e = try engine()
        transport.scriptConnect(.failure(.timedOut))
        let failed = try await e.start(binding)
        XCTAssertEqual(failed.failure?.reason, .deviceUnavailable)
        XCTAssertEqual(try vault.showerState()?.peripheralID, "PERIPHERAL-B", "the persisted idle state still knows the controller")

        transport.scriptConnect(.failure(.timedOut))
        _ = try await e.start(binding)
        XCTAssertEqual(transport.connects.map(\.preferred), ["PERIPHERAL-B", "PERIPHERAL-B"])
    }

    func testAnotherMachinesControllerIsNotPreferred() async throws {
        let other = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "99999999", roomId: "R1", roomLabel: "99栋 991")
        try vault.saveBinding(other)
        try vault.saveShowerState(ShowerState(phase: .idle, machineID: machine, peripheralID: "PERIPHERAL-B"))
        let e = try engine()
        transport.scriptConnect(.failure(.notFound))
        _ = try await e.start(other)
        XCTAssertEqual(transport.connects.map(\.preferred), [nil])
        XCTAssertNil(try vault.showerState()?.peripheralID)
    }

    func testWrongDeviceIsNotRemembered() async throws {
        try vault.saveBinding(binding)
        let e = try engine()
        transport.scriptConnect(.success("PERIPHERAL-X"))
        transport.script(.frame(FakeFrames.identity("99999999")))
        let failed = try await e.start(binding)
        XCTAssertEqual(failed.failure?.reason, .wrongDevice)
        XCTAssertNil(try vault.showerState()?.peripheralID)
        XCTAssertNil(try vault.binding()?.peripheralID)
    }

    /// The controller proved its identity before authorize; an unacknowledged write still counts.
    func testUnacknowledgedWriteStillRemembersTheController() async throws {
        try vault.saveBinding(binding)
        let e = try engine()
        transport.script(.frame(identity), .fail(.timedOut))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding)
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertEqual(try vault.binding()?.peripheralID, "PERIPHERAL-A")
    }

    /// The remembered controller answered as another machine: it is forgotten, and this start
    /// scans once without it instead of failing on it every time.
    func testRememberedControllerWithAnotherIdentityIsForgottenAndRescanned() async throws {
        var remembered = binding
        remembered.peripheralID = "PERIPHERAL-B"
        try vault.saveBinding(remembered)
        let e = try engine()
        transport.script(.frame(FakeFrames.identity("99999999")), .frame(identity), .fail(.timedOut))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(remembered)
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertEqual(transport.connects.map(\.preferred), ["PERIPHERAL-B", nil])
        XCTAssertEqual(s.peripheralID, "PERIPHERAL-A")
        XCTAssertEqual(try vault.binding()?.peripheralID, "PERIPHERAL-A")
    }

    func testRescanFindingAnotherMachineFailsWithoutRememberingEither() async throws {
        var remembered = binding
        remembered.peripheralID = "PERIPHERAL-B"
        try vault.saveBinding(remembered)
        let e = try engine()
        transport.script(.frame(FakeFrames.identity("99999999")), .frame(FakeFrames.identity("99999999")))
        let s = try await e.start(remembered)
        XCTAssertEqual(s.failure?.reason, .wrongDevice)
        XCTAssertEqual(transport.connects.count, 2, "one rescan, never a loop")
        XCTAssertNil(try vault.binding()?.peripheralID)
        XCTAssertNil(try vault.showerState()?.peripheralID)
    }

    /// `A5` (in use) carries no identity, so the controller that sent it is never remembered.
    func testBusyControllerIsNotRemembered() async throws {
        try vault.saveBinding(binding)
        let e = try engine()
        transport.script(.frame(FakeFrames.active))
        let s = try await e.start(binding)
        XCTAssertEqual(s.failure?.reason, .deviceBusy)
        XCTAssertNil(try vault.binding()?.peripheralID)
        XCTAssertNil(try vault.showerState()?.peripheralID)
    }

    /// A binding stored with a lower-case machine id remembers (and forgets) its controller
    /// the same way as an upper-case one.
    func testLowerCaseMachineIdStillRemembersTheController() async throws {
        // init upper-cases the id; a binding saved by an older build kept it as given.
        var lower = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "AABBCCDD", roomId: "R1", roomLabel: "99栋 991")
        lower.machineId = "aabbccdd"
        try vault.saveBinding(lower)
        XCTAssertEqual(try vault.binding()?.machineId, "aabbccdd", "the test really stores a lower-case id")
        let e = try engine()
        transport.script(.frame(FakeFrames.identity("AABBCCDD")), .fail(.timedOut))
        gateway.scriptAuthorize(.ok(ShowerAuthorization(machineID: "AABBCCDD", payload: auth.payload, authorizationID: "001122FF")))
        let s = try await e.start(lower)
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertEqual(try vault.binding()?.peripheralID, "PERIPHERAL-A")
    }

    func testOnlyAnIdentityFrameVerifiesTheMachine() {
        XCTAssertEqual(ShowerFrames.check(FakeFrames.identity(machine), machineID: machine), .verified)
        XCTAssertEqual(ShowerFrames.check(FakeFrames.identity(machine), machineID: machine.lowercased()), .verified)
        XCTAssertEqual(ShowerFrames.check(FakeFrames.identity("99999999"), machineID: machine), .otherMachine)
        XCTAssertEqual(ShowerFrames.check(FakeFrames.active, machineID: machine), .busy)
        XCTAssertEqual(ShowerFrames.check(Data([0x01]), machineID: machine), .unreadable)
    }
}

extension ShowerReducerTests {
    func testStartKeepsTheSameMachinesController() {
        let idle = ShowerState(phase: .idle, machineID: machine, peripheralID: "P")
        XCTAssertEqual(reduce(idle, .start(machineID: machine, preferredPeripheral: nil)).0.peripheralID, "P")
        XCTAssertNil(reduce(idle, .start(machineID: "99999999", preferredPeripheral: nil)).0.peripheralID)
        let wrong = reduce(reduce(idle, .start(machineID: machine, preferredPeripheral: "P")).0,
                           .connected(peripheralID: "Q", probe: FakeFrames.identity("99999999"))).0
        XCTAssertEqual(wrong.peripheralID, "P", "a controller with another identity never replaces the remembered one")
        XCTAssertEqual(wrong.persistable.peripheralID, "P")
    }
}
