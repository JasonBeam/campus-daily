//
//  WidgetDrawChoiceTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core
import CoreTestSupport

/// What the widget draws from what it could read (`WidgetDrawChoice`): numbers only from a read
/// that went through, the mark included; anything it could not read draws no one's numbers and
/// asks again soon.
final class WidgetDrawChoiceTests: XCTestCase {
    let previous = Money(fen: 4321)

    func seeded() throws -> KeyedFailureStore {
        let store = KeyedFailureStore()
        var s = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: Date(timeIntervalSince1970: 1_793_000_000)))
        s = SchoolSnapshotReducer.reduce(s, .balance(.success(previous), at: Date(timeIntervalSince1970: 1_793_000_000)))
        try SharedSnapshotStore(store: store).saveSnapshot(s)
        try StoredSchoolVault(store: store).saveAccount(SchoolAccount(account: "99100991"))
        return store
    }

    func choice(_ store: SecureStore) -> WidgetDrawChoice {
        WidgetDrawChoice.choose(WidgetStoredData.read(snapshots: SharedSnapshotStore(store: store), vault: StoredSchoolVault(store: store)))
    }

    func testAReadableSnapshotIsDrawn() throws {
        let store = try seeded()
        guard case .draw(let snapshot, let account) = choice(store) else { return XCTFail("readable: drawn") }
        XCTAssertEqual(snapshot?.card.value, previous)
        XCTAssertEqual(account?.account, "99100991")
    }

    func testAMarkedSnapshotWithAnUnreadableAccountDrawsNoNumbers() throws {
        let store = try seeded()
        try store.write(Data("{\"since\":0}".utf8), for: .sharedSnapshotStale)
        store.refusingReads = [.schoolPassword]
        let drawn = choice(store)
        XCTAssertEqual(drawn, .noNumbers(retryAfter: WidgetStoredData.unreadableRetry))
        XCTAssertFalse("\(drawn)".contains("4321"), "nothing of the previous person's balance")
    }

    func testAnUnreadableKeychainDrawsNoNumbersAndRetriesSoon() throws {
        let store = try seeded()
        store.refusingReads = Set(StoreKey.allCases)
        XCTAssertEqual(choice(store), .noNumbers(retryAfter: 5 * 60))
        XCTAssertEqual(WidgetDrawChoice.choose(nil), .noNumbers(retryAfter: WidgetStoredData.unreadableRetry))
    }

    func testAnUnreadableMarkerIsNotPermissionToShowNumbers() throws {
        let store = try seeded()
        store.refusingReads = [.sharedSnapshotStale]
        XCTAssertNotNil(try store.read(.sharedSnapshot), "the snapshot itself is readable")
        XCTAssertEqual(choice(store), .noNumbers(retryAfter: WidgetStoredData.unreadableRetry))
    }

    /// Non-active epochs: `.activePendingClear` hides snapshot while keeping account readable;
    /// `.switching`, `.signedOutPendingClear`, and `.signedOut` hide both snapshot and account.
    func testANonActiveEpochDrawsWithoutNumbers() throws {
        let store = try seeded()
        let vault = StoredSchoolVault(store: store)
        try vault.saveSessionEpoch(SessionEpoch(phase: .activePendingClear))
        XCTAssertEqual(choice(store), .draw(snapshot: nil, account: SchoolAccount(account: "99100991")))

        for phase in [SessionEpoch.Phase.switching, .signedOutPendingClear, .signedOut] {
            try vault.saveSessionEpoch(SessionEpoch(phase: phase))
            XCTAssertEqual(choice(store), .draw(snapshot: nil, account: nil), "phase \(phase) hides snapshot and account")
        }
    }
}
