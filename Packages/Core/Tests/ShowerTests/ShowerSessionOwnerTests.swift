//
//  ShowerSessionOwnerTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core
import CoreTestSupport

/// A session belongs to the hot-water student it was opened with (the binding's `studentId`,
/// kept in the record from its first save, by 开始洗澡 and by 开始下一次洗澡). 结束 with another
/// student's binding is refused before anything is sent; the same student's binding ends it,
/// also after the school sign-out kept that binding. Records saved before the student was kept
/// are never filled in afterwards. Fakes only, synthetic ids.
final class ShowerSessionOwnerTests: XCTestCase {
    let machine = "11223344"
    let studentA = ShowerBinding(studentId: "S-A", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let studentB = ShowerBinding(studentId: "S-B", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let next = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x40 + $0) }), authorizationID: "00AABBCC")
    let receipt = ShowerReceipt(amount: Money(fen: 163))
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
    var consumption: Data { FakeFrames.identity(machine, tail: 9) }

    var vault: RecordingShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!

    override func setUp() { reset() }

    func reset() {
        vault = RecordingShowerVault()
        transport = FakeShowerTransport()
        gateway = FakeGateway()
    }

    func engine() throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                         configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
    }

    func runningForA() async throws -> ShowerEngine {
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(studentA, permit: ShowerStartPermit())
        XCTAssertEqual(s.phase, .running)
        return e
    }

    func testStartKeepsTheStudentFromTheFirstSave() async throws {
        let e = try await runningForA()
        XCTAssertEqual(vault.saved.first??.phase, .authorizing)
        XCTAssertEqual(vault.saved.first??.studentId, "S-A", "in the first record saved")
        XCTAssertTrue(vault.saved.compactMap { $0 }.allSatisfy { $0.studentId == "S-A" })
        let st1 = await e.state
        XCTAssertEqual(st1.studentId, "S-A")
        let relaunched = try engine()
        let st2 = await relaunched.state
        XCTAssertEqual(st2.studentId, "S-A", "kept across a relaunch")
    }

    func testStartNextKeepsTheStudentFromTheFirstSave() async throws {
        // A shower over (stopped on the controller), opened by A.
        try vault.saveShowerState(ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0, authorizeSent: true,
                                              authorizationID: "001122FF", stateReviewRequired: true, studentId: "S-A"))
        let e = try engine()
        let before = vault.saved.count
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(next))
        let s = try await e.startNext(studentA, permit: ShowerStartPermit())
        XCTAssertEqual(s.phase, .running)
        let fresh = vault.saved.dropFirst(before).compactMap { $0 }
        XCTAssertEqual(fresh.first?.phase, .authorizing)
        XCTAssertEqual(fresh.first?.studentId, "S-A", "the new record's first save")
        XCTAssertEqual(s.studentId, "S-A")
        let st3 = try await engine().state
        XCTAssertEqual(st3.studentId, "S-A")
    }

    /// Another student's binding on the same controller: refused before any probe, close or
    /// settlement.
    func testAnotherStudentsBindingCannotEndIt() async throws {
        let e = try await runningForA()
        let writes = transport.writes.count, connects = transport.connects.count
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        await XCTAssertThrowsErrorAsync(try await e.finish(studentB)) { XCTAssertEqual($0 as? ShowerEngineError, .wrongBinding) }
        XCTAssertEqual(transport.writes.count, writes, "nothing written")
        XCTAssertEqual(transport.connects.count, connects, "not even connected")
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        let st4 = await e.state
        XCTAssertEqual(st4.phase, .running, "the record as it was")
        XCTAssertEqual(try vault.showerState()?.phase, .running)

        // After a relaunch too.
        let relaunched = try engine()
        await XCTAssertThrowsErrorAsync(try await relaunched.finish(studentB)) { XCTAssertEqual($0 as? ShowerEngineError, .wrongBinding) }
        XCTAssertEqual(transport.writes.count, writes)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }

    /// The student who opened it ends it; the settlement goes out under that student.
    func testTheSameStudentEndsAndSettlesUnderTheirOwnBinding() async throws {
        let e = try await runningForA()
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(studentA)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(gateway.settleFrames, [consumption])
        XCTAssertEqual(gateway.settleBindings.map(\.studentId), ["S-A"])
    }

    /// A record saved before the student was kept: it ends as before, and nothing fills the
    /// student in afterwards (not a relaunch, a check or the end).
    func testAnOlderRecordIsNeverFilledIn() async throws {
        try vault.saveShowerState(ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0,
                                              authorizeSent: true, authorizationID: "001122FF"))
        let e = try engine()
        let st5 = await e.state
        XCTAssertNil(st5.studentId)
        transport.script(.frame(FakeFrames.active))
        _ = try await e.review(studentB)
        XCTAssertNil(try vault.showerState()?.studentId)
        let st6 = await e.state
        XCTAssertNil(st6.studentId)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(studentB)
        XCTAssertEqual(done.phase, .done)
        XCTAssertNil(done.studentId)
        XCTAssertTrue(vault.saved.compactMap { $0 }.allSatisfy { $0.studentId == nil })
    }

    /// The school sign-out keeps the hot-water binding while a shower is open (it is the
    /// student's who opened it): that binding still ends and settles it.
    func testTheKeptBindingStillEndsItAfterTheSchoolSignOut() async throws {
        let e = try await runningForA()
        try vault.saveBinding(studentA)
        // The binding stays as it was; only the school login changed (nothing here reads it).
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        gateway.scriptSettle(.ok(receipt))
        let done = try await e.finish(XCTUnwrap(try vault.binding()))
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(gateway.settleBindings.map(\.studentId), ["S-A"])
    }

    /// The student stays in the Keychain record only: not in the debug log's state.
    func testTheStudentIsNotInTheDebugState() {
        let s = ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                            studentId: "S-A")
        let line = DebugEvent.showerPhase(from: .writePending, to: DebugShowerState(s)).fields { "\($0.kind.rawValue):tag" }
        XCTAssertFalse(line.contains("S-A"))
        XCTAssertFalse(String(describing: DebugShowerState(s)).contains("S-A"))
    }
}

/// A vault in memory that keeps every session record saved, in order (nil: removed).
final class RecordingShowerVault: ShowerVault, @unchecked Sendable {
    // @unchecked: `saved` guarded by `lock`.
    private let inner = StoredShowerVault(store: InMemorySecureStore())
    private let lock = NSLock()
    private var _saved: [ShowerState?] = []
    var saved: [ShowerState?] { lock.withLock { _saved } }

    func binding() throws -> ShowerBinding? { try inner.binding() }
    func saveBinding(_ binding: ShowerBinding?) throws { try inner.saveBinding(binding) }
    func showerState() throws -> ShowerState? { try inner.showerState() }
    func saveShowerState(_ state: ShowerState?) throws {
        lock.withLock { _saved.append(state) }
        try inner.saveShowerState(state)
    }
    func retainedShowers() throws -> [ShowerState] { try inner.retainedShowers() }
    func retainShower(_ state: ShowerState) throws { try inner.retainShower(state) }
}
