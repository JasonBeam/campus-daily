import XCTest
import Foundation
@testable import Core

/// Finished laundry orders kept for 最近 and 订单: only a terminal read of this record's own
/// order that ended it, with the machine and program from before the step, the amount only
/// from a 50 read, salted tags instead of ids, 7 days and 30 entries at most, per account.
final class LaundryHistoryTests: XCTestCase {
    let account = "acct-1"
    let at = L.t0.addingTimeInterval(600)

    func open(_ phase: LaundryPhase = .active) -> LaundryCheckout {
        LaundryCheckout(phase: phase, draft: L.draft, createdAt: L.t0, orderID: L.orderID, order: L.order("20"),
                        accountID: account)
    }

    func finished(_ before: LaundryCheckout, _ event: LaundryEvent) -> LaundryFinishedOrder? {
        let after = LaundryReducer.reduce(before, event).0
        return LaundryHistory.finished(before: before, event: event, after: after, accountID: nil)
    }

    func testEntryOnlyForTerminalReadOfOwnOrder() throws {
        for code in ["50", "51", "53"] {
            let before = code == "50" ? open() : open(.created)
            let entry = try XCTUnwrap(finished(before, .orderRead(L.order(code), at: at)), code)
            XCTAssertEqual(entry.status.code, code)
            XCTAssertEqual(entry.orderID, L.orderID)
            XCTAssertEqual(entry.accountID, account)
            XCTAssertEqual(entry.at, L.t0, "the local confirm time, as the open order's row")
        }
        XCTAssertNil(finished(open(), .orderRead(L.order("20"), at: at)), "not terminal")
        XCTAssertNil(finished(open(), .orderRead(L.order("50", id: "OTHER0001"), at: at)), "another order")
        XCTAssertNil(finished(open(), .orderRead(L.order("50", device: "other-device"), at: at)), "another machine")
        XCTAssertNil(finished(open(), .orderRead(L.order("50", program: 2), at: at)), "another program")
        XCTAssertNil(finished(open(), .refresh))
        // The pre-start read finishing the order counts too.
        XCTAssertEqual(finished(open(), .startCheckRead(L.check("53"), at: at))?.status.code, "53")
        // No account known at all: nothing to file it under.
        var anonymous = open(); anonymous.accountID = nil
        XCTAssertNil(finished(anonymous, .orderRead(L.order("50"), at: at)))
        let after = LaundryReducer.reduce(anonymous, .orderRead(L.order("50"), at: at)).0
        XCTAssertEqual(LaundryHistory.finished(before: anonymous, event: .orderRead(L.order("50"), at: at), after: after,
                                               accountID: "acct-9")?.accountID, "acct-9", "the signed-in account then")
    }

    func testReconcileAdoptsOnlyTheCandidate() {
        var before = LaundryCheckout(phase: .reconcile, draft: L.draft, createdAt: L.t0, accountID: account)
        before.candidateOrderID = L.orderID
        XCTAssertEqual(finished(before, .orderRead(L.order("53"), at: at))?.status.code, "53")
        before.candidateOrderID = "OTHER0001"
        XCTAssertNil(finished(before, .orderRead(L.order("53"), at: at)))
    }

    func testAttentionWrites52Once() throws {
        let before = open()
        let event = LaundryEvent.orderRead(L.order("52"), at: at)
        let after = LaundryReducer.reduce(before, event).0
        XCTAssertEqual(after.phase, .attention)
        XCTAssertEqual(LaundryHistory.finished(before: before, event: event, after: after, accountID: nil)?.status.code, "52")
        // Read again while in attention: not a new end.
        let again = LaundryReducer.reduce(after, event).0
        XCTAssertNil(LaundryHistory.finished(before: after, event: event, after: again, accountID: nil))
        // Acknowledging is not a read: nothing new.
        let acknowledged = LaundryReducer.reduce(after, .acknowledge).0
        XCTAssertNil(LaundryHistory.finished(before: after, event: .acknowledge, after: acknowledged, accountID: nil))
    }

    func testAmountOnlyPayPriceFor50() {
        // The quote (draft) is 4.00; U净's pay price says otherwise.
        XCTAssertEqual(finished(open(), .orderRead(L.order("50", price: 350), at: at))?.amount, Money(fen: 350))
        XCTAssertNil(finished(open(), .orderRead(L.order("50", price: nil), at: at))?.amount, "never the quote")
        XCTAssertNotNil(finished(open(), .orderRead(L.order("50", price: nil), at: at)))
        XCTAssertNil(finished(open(.created), .orderRead(L.order("51", price: 400), at: at))?.amount)
        XCTAssertNil(finished(open(), .orderRead(L.order("52", price: 400), at: at))?.amount)
        XCTAssertNil(finished(open(.created), .orderRead(L.order("53", price: 400), at: at))?.amount)
    }

    func testMachineAndProgramFromBeforeState() throws {
        let before = open()
        let event = LaundryEvent.orderRead(L.order("50"), at: at)
        let after = LaundryReducer.reduce(before, event).0
        XCTAssertNil(after.draft, "the record is cleared")
        let entry = try XCTUnwrap(LaundryHistory.finished(before: before, event: event, after: after, accountID: nil))
        XCTAssertEqual(entry.machine, "测试洗衣机01")
        XCTAssertEqual(entry.program, "标准洗")
    }

    // MARK: Store

    func store(_ secure: InMemorySecureStore = InMemorySecureStore(), salt: UInt8 = 7) -> LaundryHistoryStore {
        LaundryHistoryStore(store: secure, random: { Data(repeating: salt, count: 32) })
    }

    func done(_ id: String = L.orderID, account: String = "acct-1", at: Date = L.t0, status: String = "50") -> LaundryFinishedOrder {
        LaundryFinishedOrder(orderID: id, accountID: account, at: at, program: "标准洗", machine: "3",
                             status: LaundryOrderStatus(status), amount: status == "50" ? Money(fen: 400) : nil)
    }

    func testNoRawIdentifiersEncoded() throws {
        let secure = InMemorySecureStore()
        try store(secure).record(done(account: "13800000000"), now: L.t0)
        let data = try XCTUnwrap(try secure.read(.laundryHistory))
        let text = String(decoding: data, as: UTF8.self)
        for raw in [L.orderID, "13800000000", "http", L.token, L.qr, L.device] {
            XCTAssertFalse(text.contains(raw), raw)
        }
        let salt = try XCTUnwrap(try secure.read(.laundryHistorySalt))
        XCTAssertEqual(salt.count, 32)
        XCTAssertFalse(text.contains(salt.base64EncodedString()))
    }

    func testSaltCreatedOncePerInstall() throws {
        let secure = InMemorySecureStore()
        let made = Counter()
        let a = LaundryHistoryStore(store: secure, random: { made.add(); return Data(repeating: 1, count: 32) })
        try a.record(done(), now: L.t0)
        try a.record(done("TESTORDER0002"), now: L.t0)
        XCTAssertEqual(made.value, 1)
        XCTAssertEqual(a.entries(accountID: "acct-1", openOrderID: nil, now: L.t0).count, 2)

        let same = LaundryHistoryStore.tag("x", salt: Data(repeating: 1, count: 32))
        XCTAssertEqual(same, LaundryHistoryStore.tag("x", salt: Data(repeating: 1, count: 32)))
        XCTAssertNotEqual(same, LaundryHistoryStore.tag("x", salt: Data(repeating: 2, count: 32)))
        XCTAssertNotEqual(same, LaundryHistoryStore.tag("y", salt: Data(repeating: 1, count: 32)))
    }

    /// Entries without their salt are hidden and never overwritten under a new salt.
    func testMissingSaltWithEntriesHidesAndNeverOverwrites() throws {
        let secure = InMemorySecureStore()
        try store(secure).record(done(), now: L.t0)
        let kept = try secure.read(.laundryHistory)
        try secure.delete(.laundryHistorySalt)
        let s = store(secure, salt: 9)
        XCTAssertEqual(s.entries(accountID: "acct-1", openOrderID: nil, now: L.t0), [])
        XCTAssertThrowsError(try s.record(done("TESTORDER0002"), now: L.t0))
        XCTAssertNil(try secure.read(.laundryHistorySalt), "no new salt")
        XCTAssertEqual(try secure.read(.laundryHistory), kept, "untouched")
    }

    func testUnreadableStoreShowsNothingAndWritesNothing() throws {
        let secure = InMemorySecureStore()
        try store(secure).record(done(), now: L.t0)
        secure.failReads()
        XCTAssertEqual(store(secure).entries(accountID: "acct-1", openOrderID: nil, now: L.t0), [])
        XCTAssertThrowsError(try store(secure).record(done("TESTORDER0002"), now: L.t0))
        secure.failReads(false)
        XCTAssertEqual(store(secure).entries(accountID: "acct-1", openOrderID: nil, now: L.t0).count, 1)
    }

    func testPruneSevenDaysAndCap() throws {
        let s = store()
        let now = L.t0.addingTimeInterval(8 * 86400)
        try s.record(done("OLD0001", at: L.t0), now: now)
        XCTAssertEqual(s.entries(accountID: "acct-1", openOrderID: nil, now: now), [], "older than 7 days")
        for i in 0..<35 { try s.record(done("N\(i)", at: now.addingTimeInterval(TimeInterval(-i * 60))), now: now) }
        let shown = s.entries(accountID: "acct-1", openOrderID: nil, now: now)
        XCTAssertEqual(shown.count, LaundryHistory.cap)
        XCTAssertEqual(shown.first?.at, now, "newest first")
        // Age is checked when read too.
        XCTAssertEqual(s.entries(accountID: "acct-1", openOrderID: nil, now: now.addingTimeInterval(8 * 86400)), [])
        // The same order again replaces its entry.
        let one = store()
        try one.record(done(status: "52"), now: L.t0)
        try one.record(done(status: "52"), now: L.t0)
        XCTAssertEqual(one.entries(accountID: "acct-1", openOrderID: nil, now: L.t0).count, 1)
    }

    func testFutureDatedDropped() throws {
        let s = store()
        try s.record(done(at: L.t0.addingTimeInterval(3600)), now: L.t0)
        XCTAssertEqual(s.entries(accountID: "acct-1", openOrderID: nil, now: L.t0), [])
        let entry = LaundryHistoryEntry(key: "k", owner: "o", at: L.t0.addingTimeInterval(60), program: "p", machine: "m",
                                        status: "50", amount: nil)
        XCTAssertEqual(LaundryHistory.merged([], adding: entry, now: L.t0), [])
    }

    func testVisibleFiltersOwner() throws {
        let s = store()
        try s.record(done(account: "acct-1"), now: L.t0)
        try s.record(done("TESTORDER0002", account: "acct-2"), now: L.t0)
        XCTAssertEqual(s.entries(accountID: "acct-1", openOrderID: nil, now: L.t0).count, 1)
        XCTAssertEqual(s.entries(accountID: "acct-2", openOrderID: nil, now: L.t0).count, 1)
        XCTAssertEqual(s.entries(accountID: nil, openOrderID: nil, now: L.t0), [], "signed out: empty")
        XCTAssertEqual(s.entries(accountID: "acct-1", openOrderID: L.orderID, now: L.t0), [], "the open order shows as open")
    }

    // MARK: Sign-out and account change

    func testSignOutDeletesHistory() throws {
        let secure = InMemorySecureStore()
        let vault = StoredLaundryVault(store: secure)
        try vault.saveAccountItem(UjingAccountItem(mobileID: L.mobileID, account: UjingAccount(id: "acct-1", userId: "1", token: "t")))
        try store(secure).record(done(), now: L.t0)
        _ = try UjingSignOut.perform(vault: vault, preferences: UserDefaults(suiteName: UUID().uuidString)!, checkout: nil, history: store(secure))
        XCTAssertNil(try secure.read(.laundryHistory))
        XCTAssertNotNil(try secure.read(.laundryHistorySalt), "the salt stays")
    }

    func testOtherAccountLoginDeletesHistory() throws {
        let secure = InMemorySecureStore()
        try store(secure).record(done(), now: L.t0)
        XCTAssertTrue(LaundryCheckout.clearsLastOrder(record: nil, signedInAs: "acct-2", stored: "acct-1"))
        try store(secure).clear()
        XCTAssertNil(try secure.read(.laundryHistory))
        XCTAssertEqual(store(secure).entries(accountID: "acct-2", openOrderID: nil, now: L.t0), [])
    }

    func testSameAccountReloginKeepsHistory() throws {
        let secure = InMemorySecureStore()
        try store(secure).record(done(), now: L.t0)
        XCTAssertFalse(LaundryCheckout.clearsLastOrder(record: nil, signedInAs: "acct-1", stored: "acct-1"))
        XCTAssertEqual(store(secure).entries(accountID: "acct-1", openOrderID: nil, now: L.t0).count, 1)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func add() { lock.withLock { n += 1 } }
}
