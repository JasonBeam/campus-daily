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
        // Legacy 0.11.5 stale marker written directly (production no longer writes it).
        try store.write(Data("{\"since\":0}".utf8), for: .sharedSnapshotStale)
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
        XCTAssertNil(read?.account, "legacy stale mark hides account too until migrated")
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
        // Legacy 0.11.5 stale mark conservatively transitions to `.switching` and refuses refresh.
        let report = await refresher.refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .notSignedIn)
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertNil(report.snapshot.card.value, "the report has none of the previous person's numbers")
        XCTAssertNil(try snapshots.loadSnapshot()?.card.value, "nor does what was stored")
        XCTAssertEqual(try SessionEpochStore(store: store).read()?.phase, .switching)

        // Running `finishPendingClear` completes the conservative cleanup to `.signedOut`.
        refresher.finishPendingClear()
        XCTAssertEqual(try SessionEpochStore(store: store).read()?.phase, .signedOut)
        XCTAssertNil(try store.read(.sharedSnapshotStale), "cleanup drops the legacy mark")
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
        XCTAssertNil(try snapshots.loadSnapshot(), "legacy stale migrated to epoch-gated empty snapshot")
        XCTAssertNotNil(try SessionEpochStore(store: store).read(), "migrated to SessionEpoch")
        XCTAssertEqual(reader.callCount, 0, "nothing was read from the school")

        let epoch = try XCTUnwrap(try SessionEpochStore(store: store).read())
        XCTAssertEqual(epoch.phase, .signedOut, "0.11.5 stale mark conservatively migrates to .signedOut")

        // When `.active`, `finishPendingClear` leaves the current epoch's snapshot untouched.
        let activeEpoch = SessionEpoch(phase: .active)
        try SessionEpochStore(store: store).write(activeEpoch)
        var mine = previousPersonsSnapshot()
        mine.epochID = activeEpoch.id
        try snapshots.saveSnapshot(mine)
        refresher.finishPendingClear()
        XCTAssertEqual(try snapshots.loadSnapshot(), mine, "without a pending clear nothing changes")
    }

    /// No container for the lease file: the pending clear fails closed, and the mark alone keeps
    /// the numbers hidden.
    func testFinishPendingClearWithoutALeaseFileOnlyHides() throws {
        let store = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: store)
        try snapshots.saveSnapshot(previousPersonsSnapshot())
        try mark(store)
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1)),
                                          store: snapshots, lease: RefreshLease(file: nil, owner: "widget-1"))
        refresher.finishPendingClear()
        XCTAssertNotNil(try store.read(.sharedSnapshotStale))
        XCTAssertEqual(refresher.latest(), .empty)
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
