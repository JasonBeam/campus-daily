import XCTest
import Core
@testable import XiaoRiChang

/// Setting the dorm again after the person signed out or changed. The old binding stays while
/// a shower needs it, and no new shower starts with it. A shower that is over and waits for its
/// check must not hold that binding for ever: 开始下一次洗澡 is refused then, so the dorm set-up
/// keeps the record (as 开始下一次洗澡 does) and replaces the binding.
@MainActor
final class ShowerRebindTests: XCTestCase {
    private let next = ShowerBinding(studentId:"S-2", schoolId:"1", machineId:"AABBCCDD", roomId:"R-2", roomLabel:"99栋 992")

    private func model(record: ShowerState) async throws -> (ShowerModel, StoredShowerVault) {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(record)
        let (model, _) = liveShowerModel(store:store)
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded }
        return (model, vault)
    }

    func testTheDormCanBeSetAgainOverAShowerThatWaitsForItsCheck() async throws {
        let (model, vault) = try await model(record:Fixture.awaitingReview)
        XCTAssertEqual(model.clearBindingForAccountSwitch(), .keptForReview)
        XCTAssertFalse(model.mayImport)
        XCTAssertFalse(model.mayStartNext)
        XCTAssertTrue(model.mayRebind)

        try model.saveBinding(next)
        await waitUntil { model.gateRecord != .notLoaded }

        XCTAssertEqual(try vault.binding(), next)
        XCTAssertFalse(model.residenceReviewRequired)
        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertNil(try vault.showerState())
        XCTAssertEqual(try vault.retainedShowers().map(\.phase), [.failed], "kept, not dropped")
        XCTAssertNil(model.retained, "the other student's")
    }

    /// A row an earlier build kept for an open shower without its controller doesn't stop the
    /// dorm from being set again: the waiting record is kept after it, under the old student.
    func testRebindingOverAWaitingRecordWorksBesideALegacyRow() async throws {
        let store = ScriptedStore()
        let legacy = Data(#"[{"phase":"running","machineID":"11223344","stateReviewRequired":true}]"#.utf8)
        try store.write(legacy, for: .showerRetained)
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(Fixture.awaitingReview)
        let (model, _) = liveShowerModel(store:store)
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded }
        XCTAssertEqual(model.clearBindingForAccountSwitch(), .keptForReview)

        try model.saveBinding(next)
        await waitUntil { model.gateRecord != .notLoaded }

        XCTAssertEqual(try vault.binding(), next)
        XCTAssertNil(try vault.showerState())
        let stored = try XCTUnwrap(store.read(.showerRetained))
        XCTAssertEqual(stored.prefix(legacy.count - 1), legacy.dropLast(), "the old row stays as it was")
        let rows = try XCTUnwrap(JSONValue.parse(stored).array)
        XCTAssertEqual(rows.count, 2)
        XCTAssertNil(rows[0]["keptFor"])
        XCTAssertEqual(rows[1]["keptFor"], .string(Fixture.binding.studentId))
        XCTAssertEqual(try vault.retainedShowers().last?.phase, .failed)
    }

    /// The same record without a change of person: the binding is this person's, and
    /// 开始下一次洗澡 is the way on.
    func testWithoutAChangeOfPersonTheRecordStillBlocksANewDorm() async throws {
        let (model, vault) = try await model(record:Fixture.awaitingReview)
        XCTAssertFalse(model.mayRebind)
        XCTAssertThrowsError(try model.saveBinding(next))
        XCTAssertEqual(try vault.binding(), Fixture.binding)
        XCTAssertEqual(try vault.retainedShowers(), [])
    }

    /// Water may still run: the binding is what 结束 needs.
    func testAShowerThatMayBeOpenStillBlocksANewDorm() async throws {
        let (model, vault) = try await model(record:Fixture.running)
        XCTAssertEqual(model.clearBindingForAccountSwitch(), .keptForReview)
        XCTAssertFalse(model.mayRebind)
        XCTAssertThrowsError(try model.saveBinding(next))
        XCTAssertEqual(try vault.binding(), Fixture.binding)
    }
}
