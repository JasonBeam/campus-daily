import XCTest
@testable import Core

/// The showers a next use kept (`water.retained`), shown read-only: how many there are and, for
/// each, when it started, on which controller and why it was kept. Nothing on it settles,
/// deletes or sends anything. Fakes only.
final class ShowerRetainedSummaryTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func failed(_ reason: ShowerFailureReason, at start: Date?) -> ShowerState {
        ShowerState(phase: .failed, machineID: "11223344", startedAt: start,
                    failure: ShowerFailure(reason: reason, needsReview: true))
    }

    var stopped: ShowerState {
        ShowerState(phase: .running, machineID: "AABBCCDD", startedAt: t0, stateReviewRequired: true)
    }

    func vault(keeping records: [ShowerState]) throws -> StoredShowerVault {
        let vault = StoredShowerVault(store: InMemorySecureStore())
        for record in records { try vault.retainShower(record) }
        return vault
    }

    func testCountsKeptRecords() throws {
        let later = t0.addingTimeInterval(3600)
        let vault = try vault(keeping: [stopped, failed(.closeUnconfirmed, at: later), failed(.settleUncertain, at: later.addingTimeInterval(60))])
        let summary = try XCTUnwrap(ShowerRetainedSummary.read(vault))
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.entries.map(\.reason), [.stopped, .closeUnconfirmed, .settleUnconfirmed])
        XCTAssertEqual(summary.entries.map(\.started), [t0, later, later.addingTimeInterval(60)])
        XCTAssertEqual(summary.entries.map(\.machine), ["AABBCCDD", "11223344", "11223344"])
        XCTAssertNil(summary.currentMachine, "no binding saved")
    }

    /// The summary knows the dorm's controller, so the lists can leave it out.
    func testCarriesTheDormsController() throws {
        let vault = try vault(keeping: [stopped])
        try vault.saveBinding(ShowerBinding(studentId: "S-1", schoolId: "1", machineId: "aabbccdd", roomId: "R-1", roomLabel: "3栋108"))
        XCTAssertEqual(try XCTUnwrap(ShowerRetainedSummary.read(vault)).currentMachine, "AABBCCDD")
    }

    func testBusyCloseReadsAsCloseUnconfirmed() {
        XCTAssertEqual(ShowerRetainedSummary(records: [failed(.closeBusy, at: t0)]).entries.first?.reason, .closeUnconfirmed)
    }

    func testEverySettleOutcomeReadsAsSettleUnconfirmed() {
        for reason in [ShowerFailureReason.settleRefused, .settleUncertain, .settleUnconfirmed] {
            XCTAssertEqual(ShowerRetainedSummary(records: [failed(reason, at: t0)]).entries.first?.reason, .settleUnconfirmed, reason.rawValue)
        }
        XCTAssertEqual(ShowerRetainedSummary(records: [failed(.authorizeUncertain, at: nil)]).entries.first?.reason, .authorizeUnclear)
        XCTAssertNil(ShowerRetainedSummary(records: [failed(.authorizationInvalid, at: nil)]).entries.first?.started)
    }

    func testUnreadableListShowsNothing() throws {
        let store = InMemorySecureStore()
        try store.write(Data("not json".utf8), for: .showerRetained)
        XCTAssertNil(ShowerRetainedSummary.read(StoredShowerVault(store: store)), "a list that can't be decoded")

        let locked = InMemorySecureStore()
        locked.failReads()
        XCTAssertNil(ShowerRetainedSummary.read(StoredShowerVault(store: locked)), "a Keychain that can't be read")

        XCTAssertNil(ShowerRetainedSummary.read(StoredShowerVault(store: InMemorySecureStore())), "none kept: no line")
    }

    /// Display fields only: no handle on the stored records, no settle or delete.
    func testNoActionsOffered() throws {
        let summary = try XCTUnwrap(ShowerRetainedSummary.read(try vault(keeping: [stopped])))
        XCTAssertEqual(Mirror(reflecting: summary).children.compactMap(\.label), ["entries", "currentMachine"])
        XCTAssertEqual(Mirror(reflecting: summary.entries[0]).children.compactMap(\.label), ["started", "machine", "reason"])
        // Reading it changes nothing.
        let vault = try vault(keeping: [stopped])
        _ = ShowerRetainedSummary.read(vault)
        XCTAssertEqual(try vault.retainedShowers(), [stopped])
    }

    // MARK: Words

    func testClearWords() {
        XCTAssertEqual(ShowerRetainedText.Clear.line(count: 3), "已保留 3 笔费用待核对记录。可在校园卡消费明细中核对，扣费约 1 小时后入账。")
        XCTAssertEqual(ShowerRetainedText.Clear.spoken(count: 3), "已保留 3 笔费用待核对记录，轻点两下查看")
        XCTAssertEqual(ShowerRetainedText.Clear.sectionTitle, "待核对的热水记录")
        XCTAssertEqual(ShowerRetainedText.Clear.footer, "可在校园卡消费明细中核对，扣费约 1 小时后入账。")
        XCTAssertEqual(ShowerRetainedText.Clear.reason(.stopped), "停水未结算")
        XCTAssertEqual(ShowerRetainedText.Clear.reason(.closeUnconfirmed), "关水未确认")
        XCTAssertEqual(ShowerRetainedText.Clear.reason(.settleUnconfirmed), "结算未确认")
    }

    func testWarmWords() {
        XCTAssertEqual(ShowerRetainedText.Warm.line(count: 2), "有 2 次洗澡没在 App 里结算，点开看看")
        XCTAssertEqual(ShowerRetainedText.Warm.listTitle, "没结算的洗澡")
        XCTAssertEqual(ShowerRetainedText.Warm.footer, "这些记录只留给你核对，App 不会再为它们扣钱。去校园卡记录里对一下，扣费要 1 小时左右才出现。")
        XCTAssertEqual(ShowerRetainedText.Warm.reason(.stopped), "在水控上按停的")
        XCTAssertEqual(ShowerRetainedText.Warm.reason(.closeUnconfirmed), "结束没确认")
        XCTAssertEqual(ShowerRetainedText.Warm.reason(.settleUnconfirmed), "结算没确认")
    }
}
