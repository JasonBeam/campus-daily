import XCTest
import Core
@testable import XiaoRiChang

/// The live `ShowerModel` and 「先看看示例」's gate (`LiveShowerGate`), on fake stores: the sample
/// stays shut until the model mirrors a record it has read, and whenever that record can't be
/// read; a live step and the sample never overlap.
@MainActor
final class ShowerModelGateTests: XCTestCase {
    /// The model rebuilds its engine (a binding saved): until the new engine's record is mirrored
    /// here the sample stays shut, even within the same main-actor step, and then the running
    /// record keeps it shut. Before: the earlier, failed read let it open on a stale idle.
    func testRebuiltEngineKeepsTheSampleShutUntilItsRecordIsMirrored() async throws {
        let store = ScriptedStore()
        store.sessionReadError = { $0 == 0 ? StorageError(operation: "read", status: -25308) : nil }
        let (model, sample) = liveShowerModel(store: store)
        XCTAssertEqual(model.gateRecord, .unreadable, "the first read failed")

        try StoredShowerVault(store: store).saveShowerState(Fixture.running)
        try model.saveBinding(Fixture.binding)
        XCTAssertEqual(sample.enter(), .refused, "the rebuilt engine's record is not mirrored yet")

        await waitUntil { model.gateRecord != .notLoaded }
        XCTAssertEqual(model.state.phase, .running)
        XCTAssertEqual(sample.enter(), .refused, "a running shower")
        XCTAssertFalse(sample.isActive)
    }

    /// The engine can't read the record (a plain Keychain error, after a first read found none):
    /// the sample stays shut. Before: the first read's idle let it open.
    func testARecordTheEngineCannotReadKeepsTheSampleShut() async throws {
        let store = ScriptedStore()
        try StoredShowerVault(store: store).saveBinding(Fixture.binding)
        store.sessionReadError = { $0 >= 1 ? StorageError(operation: "read", status: -25308) : nil }
        let (model, sample) = liveShowerModel(store: store)
        await model.reloadProfile()
        XCTAssertTrue(model.storageBlocked)
        XCTAssertEqual(sample.enter(), .refused)
        XCTAssertFalse(sample.isActive)
    }

    /// The same model over a record at rest: the sample opens once the record is mirrored.
    func testARecordAtRestOpensTheSampleOnceMirrored() async throws {
        let store = ScriptedStore()
        try StoredShowerVault(store: store).saveBinding(Fixture.binding)
        let (model, sample) = liveShowerModel(store: store)
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded }
        XCTAssertEqual(model.gateRecord, .known(.idle))
        XCTAssertEqual(sample.enter(), .entered)
    }

    /// 再结算一次 (`confirmSettleRetry`) on a record awaiting review and entering the sample, in
    /// both orders, with the settle held at a fake platform: exactly one goes through, and
    /// nothing is sent while the sample is shown.
    func testSettleRetryAndEnteringTheSampleLetOnlyOneThrough() async throws {
        for retryFirst in [true, false] {
            let store = ScriptedStore()
            let vault = StoredShowerVault(store: store)
            try vault.saveBinding(Fixture.binding)
            try vault.saveShowerState(Fixture.awaitingReview)
            let http = HeldHTTP()
            let (model, sample) = liveShowerModel(store: store, support: try Fixture.supportWithProfile(), showerHTTP: http)
            await model.reloadProfile()
            await waitUntil { model.gateRecord != .notLoaded }
            XCTAssertTrue(model.state.canRetrySettle, "retry first: \(retryFirst)")
            await model.requestSettleRetry()
            XCTAssertTrue(model.state.settleRetryArmed)

            if retryFirst {
                let retry = Task { await model.confirmSettleRetry() }
                let reached = await http.reached()
                XCTAssertTrue(reached, "the settle reached the platform: \(String(describing: model.state.failure)) \(model.message ?? "")")
                guard reached else { retry.cancel(); http.release(); continue }
                XCTAssertEqual(sample.enter(), .refused, "the settle is at the platform")
                http.release()
                await retry.value
                XCTAssertEqual(http.sent, 1)
                XCTAssertEqual(sample.enter(), .entered, "the retry is over")
            } else {
                XCTAssertEqual(sample.enter(), .entered)
                await model.confirmSettleRetry()
                http.release()
                XCTAssertEqual(http.sent, 0, "nothing sent while the sample is shown")
                XCTAssertTrue(model.state.canRetrySettle)
                XCTAssertTrue(sample.isActive)
            }
        }
    }
}
