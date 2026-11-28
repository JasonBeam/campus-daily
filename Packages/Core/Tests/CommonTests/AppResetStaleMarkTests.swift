//
//  AppResetStaleMarkTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core
import CoreTestSupport

/// 重置 and the mark that hides the previous person's snapshot: the mark goes only once the
/// snapshot is gone (deleted, or never there). A snapshot that can't be deleted keeps it, so
/// neither the app, a relaunch nor the widget reads the old numbers after a reset that did not finish.
final class AppResetStaleMarkTests: XCTestCase {
    let previous = Money(fen: 4321)

    func seed(_ store: SecureStore) throws {
        var s = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: Date(timeIntervalSince1970: 1_793_000_000)))
        s = SchoolSnapshotReducer.reduce(s, .balance(.success(previous), at: Date(timeIntervalSince1970: 1_793_000_000)))
        try SharedSnapshotStore(store: store).saveSnapshot(s)
        try StoredSchoolVault(store: store).saveAccount(SchoolAccount(account: "99100991"))
        try StoredSchoolVault(store: store).saveSessionEpoch(SessionEpoch(phase: .signedOutPendingClear))
        try store.write(Data("{\"since\":0}".utf8), for: .sharedSnapshotStale)
    }

    func reset(_ store: SecureStore) throws {
        let suite = "reset-stale-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try AppReset.clear(store: store, preferences: defaults, preferencesDomain: suite, shared: nil, files: [])
    }

    func testAResetKeepsTheMarkWhileTheSnapshotCannotBeDeleted() throws {
        let store = KeyedFailureStore()
        try seed(store)
        store.refusingDeletes = [.sharedSnapshot]
        do {
            try reset(store)
            XCTFail("the snapshot could not be deleted")
        } catch let failure as AppReset.Failure {
            XCTAssertTrue(failure.items.contains("shared.snapshot"), "\(failure.items)")
            XCTAssertFalse(failure.items.contains("shared.snapshotStale"), "\(failure.items)")
        }
        XCTAssertNotNil(try store.read(.sharedSnapshotStale), "the legacy mark stays while the snapshot does")
        XCTAssertNotNil(try store.read(.sharedSessionEpoch), "the epoch stays while the snapshot does")
        XCTAssertNil(try store.read(.schoolPassword), "the rest was cleared all the same")
        let refresher = SnapshotRefresher(school: StaticReader(), store: SharedSnapshotStore(store: store))
        XCTAssertEqual(refresher.latest(), .empty)
        XCTAssertNil(try SharedSnapshotStore(store: store).loadSnapshot(), "read again (a relaunch)")
        XCTAssertNil(WidgetStoredData.read(snapshots: SharedSnapshotStore(store: store), vault: StoredSchoolVault(store: store))?.snapshot)

        store.refusingDeletes = []
        try reset(store)
        XCTAssertNil(try store.read(.sharedSnapshot))
        XCTAssertNil(try store.read(.sharedSnapshotStale))
        XCTAssertNil(try store.read(.sharedSessionEpoch))
    }

    func testAResetWithNoSnapshotDeletesTheMark() throws {
        let store = KeyedFailureStore()
        try StoredSchoolVault(store: store).saveSessionEpoch(SessionEpoch(phase: .signedOutPendingClear))
        try store.write(Data("{\"since\":0}".utf8), for: .sharedSnapshotStale)
        XCTAssertNil(try store.read(.sharedSnapshot))
        try reset(store)
        XCTAssertNil(try store.read(.sharedSnapshotStale))
        XCTAssertNil(try store.read(.sharedSessionEpoch))
    }

    func testAResetKeepsTheEpochWhileAnySchoolItemCannotBeDeleted() throws {
        let store = KeyedFailureStore()
        try seed(store)
        store.refusingDeletes = [.schoolPassword]
        do {
            try reset(store)
            XCTFail("school.password could not be deleted")
        } catch let failure as AppReset.Failure {
            XCTAssertTrue(failure.items.contains("school.password"), "\(failure.items)")
            XCTAssertFalse(failure.items.contains("shared.sessionEpoch"), "\(failure.items)")
        }
        XCTAssertNil(try store.read(.sharedSnapshot), "the snapshot itself was deleted")
        XCTAssertNotNil(try store.read(.sharedSessionEpoch), "the epoch stays while any school item remains")
        store.refusingDeletes = []
        try reset(store)
        XCTAssertNil(try store.read(.sharedSessionEpoch))
    }

    /// The mark itself can't be deleted: the reset says so (and is tried again).
    func testAMarkThatCannotBeDeletedIsReported() throws {
        let store = KeyedFailureStore()
        try seed(store)
        store.refusingDeletes = [.sharedSnapshotStale]
        do {
            try reset(store)
            XCTFail("the mark could not be deleted")
        } catch let failure as AppReset.Failure {
            XCTAssertEqual(failure.items, ["shared.snapshotStale"])
        }
        XCTAssertNil(try store.read(.sharedSnapshot))
    }

    private struct StaticReader: PlainSchoolReader {
        func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool) async -> SchoolReading {
            SchoolReading(outcome: .notSignedIn, checkedAt: Date())
        }
    }
}
