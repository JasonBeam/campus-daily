//
//  SnapshotStaleMarkerTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core
import CoreTestSupport

/// The snapshot left by the previous person while its clean-up could not write (`shared.snapshotStale`):
/// no reader shows it, the next write that succeeds replaces it and drops the mark, and a pending
/// clear finishes without the network.
final class SnapshotStaleMarkerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_793_000_000)
    let t1 = Date(timeIntervalSince1970: 1_793_003_600)
    let previous = Money(fen: 4321)

    func previousPersonsSnapshot() -> HomeSnapshot {
        var s = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: t0))
        s = SchoolSnapshotReducer.reduce(s, .balance(.success(previous), at: t0))
        return s
    }

    func mark(_ store: SecureStore) throws {
        try StoredSchoolVault(store: store).markSnapshotStale(since: t0)
    }

    func testAMarkedSnapshotReadsAsNothing() throws {
        let store = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: store)
        try snapshots.saveSnapshot(previousPersonsSnapshot())
        try StoredSchoolVault(store: store).saveAccount(SchoolAccount(account: "99100991"))
        try mark(store)
        XCTAssertNotNil(try store.read(.sharedSnapshotStale))
        XCTAssertNotNil(try store.read(.sharedSnapshot), "the bytes are still there")

        XCTAssertNil(try snapshots.loadSnapshot())
        XCTAssertEqual(SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1)), store: snapshots).latest(), .empty)
        let read = WidgetStoredData.read(snapshots: snapshots, vault: StoredSchoolVault(store: store))
        XCTAssertNotNil(read)
        XCTAssertNil(read?.snapshot)
        XCTAssertEqual(read?.account?.account, "99100991", "the account reads as usual")
    }

    /// The mark is only looked for, never decoded: a damaged one still hides.
    func testADamagedMarkStillHides() throws {
        let store = InMemorySecureStore()
        try SharedSnapshotStore(store: store).saveSnapshot(previousPersonsSnapshot())
        try store.write(Data("not json".utf8), for: .sharedSnapshotStale)
        XCTAssertNil(try SharedSnapshotStore(store: store).loadSnapshot())
    }

    func testAnOfflineRefreshAfterTheMarkCarriesNoOldNumbers() async throws {
        let store = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: store)
        try snapshots.saveSnapshot(previousPersonsSnapshot())
        try mark(store)
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .failed(.offline), checkedAt: t1)),
                                          store: snapshots)
        let report = await refresher.refresh(inBackground: false)
        XCTAssertTrue(report.snapshotSaved)
        XCTAssertNil(report.snapshot.card.value, "the report has none of the previous person's numbers")
        XCTAssertNil(try snapshots.loadSnapshot()?.card.value, "nor does what was stored")
        XCTAssertNil(try store.read(.sharedSnapshotStale), "a write that went through drops the mark")
    }

    func testAClearThatCannotWriteKeepsTheMarkAndHides() async throws {
        let store = KeyedFailureStore()
        let snapshots = SharedSnapshotStore(store: store)
        try snapshots.saveSnapshot(previousPersonsSnapshot())
        try mark(store)
        store.refusingWrites = [.sharedSnapshot]
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1)), store: snapshots)
        do { try await refresher.clear(); XCTFail("the snapshot write was refused") } catch {}
        XCTAssertNotNil(try store.read(.sharedSnapshotStale), "the mark stays")
        XCTAssertEqual(refresher.latest(), .empty)
    }

    func testAMarkThatCannotBeDeletedKeepsHidingUntilTheNextSave() throws {
        let store = KeyedFailureStore()
        let events = EventLog()
        let snapshots = SharedSnapshotStore(store: store, diagnostic: { events.append($0) })
        try snapshots.saveSnapshot(previousPersonsSnapshot())
        try mark(store)
        store.refusingDeletes = [.sharedSnapshotStale]
        let next = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: t1))
        try snapshots.saveSnapshot(next)
        XCTAssertNotNil(try store.read(.sharedSnapshotStale), "the mark could not be deleted")
        XCTAssertNil(try snapshots.loadSnapshot(), "still hidden")
        XCTAssertEqual(events.all, ["snapshot.staleClearFailed status=-25308"])

        store.refusingDeletes = []
        try snapshots.saveSnapshot(next)
        XCTAssertNil(try store.read(.sharedSnapshotStale))
        XCTAssertEqual(try snapshots.loadSnapshot(), next)
    }

    func testFinishPendingClearWorksOffline() throws {
        let store = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: store)
        let reader = ScriptedSchoolReader(SchoolReading(outcome: .failed(.offline), checkedAt: t1))
        let refresher = SnapshotRefresher(school: reader, store: snapshots,
                                          lease: RefreshLease(file: store.leaseFile, owner: "widget-1"))
        try snapshots.saveSnapshot(previousPersonsSnapshot())
        try mark(store)
        refresher.finishPendingClear()
        XCTAssertNil(try store.read(.sharedSnapshotStale))
        XCTAssertEqual(try snapshots.loadSnapshot(), .empty, "the previous person's bytes are replaced")
        XCTAssertEqual(reader.callCount, 0, "nothing was read from the school")

        let mine = previousPersonsSnapshot()
        try snapshots.saveSnapshot(mine)
        refresher.finishPendingClear()
        XCTAssertEqual(try snapshots.loadSnapshot(), mine, "without a mark nothing changes")
    }

    /// No container for the lease file (`RefreshLease.locked` would just run the body): the
    /// pending clear is skipped, and the mark alone keeps the numbers hidden.
    func testFinishPendingClearWithoutALeaseFileOnlyHides() throws {
        let store = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: store)
        try snapshots.saveSnapshot(previousPersonsSnapshot())
        try mark(store)
        for lease in [nil, RefreshLease(file: nil, owner: "widget-1")] {
            let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1)),
                                              store: snapshots, lease: lease)
            refresher.finishPendingClear()
            XCTAssertNotNil(try store.read(.sharedSnapshotStale))
            XCTAssertEqual(refresher.latest(), .empty)
        }
    }

    func testTheWidgetsReadDrawsNothingOldWhileMarked() async throws {
        let store = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: store)
        var old = previousPersonsSnapshot()
        old.checkedAt = Date(timeIntervalSinceNow: -3600)
        try snapshots.saveSnapshot(old)
        try mark(store)
        let reader = ScriptedSchoolReader(SchoolReading(outcome: .failed(.timedOut), checkedAt: Date()))
        let refresher = SnapshotRefresher(school: reader, store: snapshots)
        let drawn = await WidgetRefresh.run(refresher, now: Date(), deadline: 0)
        XCTAssertEqual(drawn, .empty)
        XCTAssertNil(drawn.card.value)
    }
}
