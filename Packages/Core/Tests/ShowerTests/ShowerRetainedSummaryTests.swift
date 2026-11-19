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
        ShowerState(phase: .running, machineID: "AABBCCDD", peripheralID: "P", startedAt: t0, stateReviewRequired: true)
    }

    func binding(_ student: String, machine: String = "11223344") -> ShowerBinding {
        ShowerBinding(studentId: student, schoolId: "1", machineId: machine, roomId: "R-1", roomLabel: "3栋108")
    }

    /// Kept under a saved binding, as a next use keeps them.
    func vault(keeping records: [ShowerState]) throws -> StoredShowerVault {
        let vault = StoredShowerVault(store: InMemorySecureStore())
        try vault.saveBinding(binding("S-1"))
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
    }

    /// The summary knows the dorm's controller, so the lists can leave it out.
    func testCarriesTheDormsController() throws {
        let vault = try vault(keeping: [stopped])
        try vault.saveBinding(binding("S-1", machine: "aabbccdd"))
        XCTAssertEqual(try XCTUnwrap(ShowerRetainedSummary.read(vault)).currentMachine, "AABBCCDD")
    }

    /// A kept record is read only under a binding of the student it was kept for: after a
    /// sign-out or for the next person on the phone it is not shown. It stays stored, and the
    /// same student sees it again once the dorm is set up again.
    func testOnlyTheBoundStudentsRecordsAreRead() throws {
        let vault = try vault(keeping: [stopped])
        let other = failed(.settleUncertain, at: t0.addingTimeInterval(60))
        try vault.saveBinding(binding("S-2"))
        try vault.retainShower(other)
        XCTAssertEqual(ShowerRetainedSummary.read(vault)?.entries.map(\.reason), [.settleUnconfirmed])

        try vault.saveBinding(nil)
        XCTAssertNil(ShowerRetainedSummary.read(vault), "nobody's without a binding")

        try vault.saveBinding(binding("S-1"))
        XCTAssertEqual(ShowerRetainedSummary.read(vault)?.entries.map(\.reason), [.stopped])
        XCTAssertEqual(try vault.retainedShowers(), [stopped, other], "none dropped")
    }

    /// A list an earlier build wrote names no student: its records stay stored and are not shown.
    func testARecordThatNamesNoStudentIsKeptButNotShown() throws {
        let store = InMemorySecureStore()
        try store.writeJSON([stopped], .showerRetained)
        let vault = StoredShowerVault(store: store)
        try vault.saveBinding(binding("S-1"))
        XCTAssertNil(ShowerRetainedSummary.read(vault))
        try vault.retainShower(failed(.closeUnconfirmed, at: t0))
        XCTAssertEqual(try vault.retainedShowers().count, 2)
        XCTAssertEqual(ShowerRetainedSummary.read(vault)?.count, 1)
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

    // MARK: The card's charge

    /// One kept shower the card's records show charged: a third line, the same in both themes,
    /// and VoiceOver hears it at the end of the row.
    func testAChargedShowerGetsItsLine() {
        XCTAssertEqual(ShowerRetainedText.charged(Money(fen: 132)), "校园卡已扣 ¥1.32")
        XCTAssertEqual(ShowerRetainedText.chargedSpoken(Money(fen: 132)), "校园卡已扣 1.32 元")
        XCTAssertEqual(ShowerRetainedText.charged(Money(fen: 1)), "校园卡已扣 ¥0.01")
        let later = t0.addingTimeInterval(3600)
        let summary = ShowerRetainedSummary(records: [stopped, failed(.closeUnconfirmed, at: later)], currentMachine: "11223344")
        let lines = ShowerRetainedText.lines(summary, reason: ShowerRetainedText.Warm.reason, time: { $0 == t0 ? "early" : "late" },
                                             charge: { $0 == t0 ? Money(fen: 132) : nil })
        XCTAssertEqual(lines.map(\.charge), [nil, "校园卡已扣 ¥1.32"])
        XCTAssertEqual(lines[1].spoken, "early，水控 AABBCCDD · 在水控上按停的，校园卡已扣 1.32 元")
        XCTAssertEqual(lines[0].spoken, "late，结束没确认", "nothing said when nothing matched")
    }

    /// Without a charge (or no ledger) the rows are as before.
    func testNoChargeLeavesTheRowsAlone() {
        let summary = ShowerRetainedSummary(records: [stopped])
        let lines = ShowerRetainedText.lines(summary, reason: ShowerRetainedText.Clear.reason, time: { _ in "T" })
        XCTAssertEqual(lines, [ShowerRetainedText.Line(title: "T", detail: "水控 AABBCCDD · 停水未结算")])
        XCTAssertNil(lines[0].charge)
    }
}
