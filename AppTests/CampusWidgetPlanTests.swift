//
//  CampusWidgetPlanTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
import Core
@testable import XiaoRiChang

/// What the widget's provider draws (`CampusWidgetPlan`, from `WidgetDrawChoice`): nothing it
/// could not read this time is drawn with numbers, whatever it drew before, and a timeline is
/// never empty (an empty one could leave the face on screen as it is).
@MainActor
final class CampusWidgetPlanTests: XCTestCase {
    private static let previousBalance = Money(fen:4321)
    private let now = Date(timeIntervalSince1970:1_793_000_000)

    private func seeded() throws -> ScriptedStore {
        let store = ScriptedStore()
        var numbers = HomeSnapshot(checkedAt:now.addingTimeInterval(-60))
        numbers.card.succeed(Self.previousBalance, at:now.addingTimeInterval(-60))
        try SharedSnapshotStore(store:store).saveSnapshot(numbers)
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        return store
    }

    private func choice(_ store: SecureStore) -> WidgetDrawChoice {
        WidgetDrawChoice.choose(WidgetStoredData.read(snapshots:SharedSnapshotStore(store:store), vault:StoredSchoolVault(store:store)))
    }

    private func showsPrevious(_ model: CampusWidgetModel) -> Bool {
        !model.placeholder && model.balance == Self.previousBalance.yuan
    }

    func testTheProviderNeverRedrawsAnOldNumberedEntry() throws {
        let store = try seeded()
        let first = CampusWidgetPlan.face(choice(store), now:now, preview:false, lines:ReminderLines())
        XCTAssertTrue(showsPrevious(first), "drawn with A's numbers first")

        try store.write(Data("{\"since\":0}".utf8), for:.sharedSnapshotStale)
        store.refusingReads = [.schoolPassword]
        let later = choice(store)
        let face = CampusWidgetPlan.face(later, now:now, preview:false, lines:ReminderLines())
        XCTAssertFalse(showsPrevious(face), "getSnapshot")
        XCTAssertTrue(face.placeholder, "no one's numbers: the grey bars")
        let timeline = CampusWidgetPlan.timeline(later, drawn:nil, now:now, interval:30 * 60, lines:ReminderLines())
        XCTAssertFalse(timeline.faces.isEmpty)
        XCTAssertFalse(timeline.faces.contains { showsPrevious($0.model) }, "getTimeline")
    }

    func testABlankDrawnBySnapshotIsNotUndoneByALaterUnreadableTimeline() throws {
        let store = try seeded()
        try StoredSchoolVault(store:store).saveSessionEpoch(SessionEpoch(phase:.activePendingClear))
        let blank = CampusWidgetPlan.face(choice(store), now:now, preview:false, lines:ReminderLines())
        XCTAssertFalse(showsPrevious(blank))
        XCTAssertNil(blank.balance, "marked: drawn without numbers")

        store.refusingReads = Set(StoreKey.allCases)
        let unreadable = choice(store)
        let timeline = CampusWidgetPlan.timeline(unreadable, drawn:nil, now:now, interval:30 * 60, lines:ReminderLines())
        XCTAssertFalse(timeline.faces.isEmpty)
        XCTAssertFalse(timeline.faces.contains { showsPrevious($0.model) })
    }

    func testNoCacheAndUnreadableStillYieldsOneNoNumberEntry() {
        let timeline = CampusWidgetPlan.timeline(WidgetDrawChoice.choose(nil), drawn:nil, now:now, interval:30 * 60, lines:ReminderLines())
        XCTAssertEqual(timeline.faces.count, 1)
        XCTAssertEqual(timeline.faces.first?.date, now)
        XCTAssertEqual(timeline.faces.first?.model.placeholder, true)
        XCTAssertEqual(timeline.next, now.addingTimeInterval(WidgetStoredData.unreadableRetry), "asks again soon")
    }

    /// A read that went through draws what the widget's refresh returned, and asks again later.
    func testAReadableStoreDrawsTheRefreshedSnapshot() throws {
        let store = try seeded()
        let drawn = try XCTUnwrap(try SharedSnapshotStore(store:store).loadSnapshot())
        let timeline = CampusWidgetPlan.timeline(choice(store), drawn:drawn, now:now, interval:30 * 60, lines:ReminderLines())
        XCTAssertEqual(timeline.faces.first?.model.balance, Self.previousBalance.yuan)
        XCTAssertEqual(timeline.faces.first?.model.placeholder, false)
        XCTAssertEqual(timeline.next, now.addingTimeInterval(30 * 60))
    }

    // MARK: - Revo #3: Delivery boundaries for getSnapshot & getTimeline

    private struct FailingCommitLock: SharedLock {
        func locked<T>(_ body: () throws -> T) throws -> T { throw CocoaError(.fileLocking) }
    }

    private final class DeliveryBox<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Value?
        func set(_ value: Value) { lock.withLock { storage = value } }
        var value: Value? { lock.withLock { storage } }
    }

    private func seededActiveEpoch(_ id: String = "E1") throws -> ScriptedStore {
        let store = ScriptedStore()
        try StoredSchoolVault(store:store).saveSessionEpoch(SessionEpoch(id:id, phase:.active))
        var numbers = HomeSnapshot(checkedAt:now.addingTimeInterval(-60))
        numbers.epochID = id
        numbers.card.succeed(Self.previousBalance, at:now.addingTimeInterval(-60))
        try SharedSnapshotStore(store:store).saveSnapshot(numbers)
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        return store
    }

    /// Revo #3 (`getSnapshot`): even after A's candidate face and reminder lines were built,
    /// an epoch transition right before commit-lock verification discards A's numbers before
    /// invoking `completion`.
    func testDeliverSnapshotDropsCandidateWhenEpochChangesBeforeCommitLock() throws {
        let store = try seededActiveEpoch("E1")
        let vault = StoredSchoolVault(store:store)
        let snapshots = SharedSnapshotStore(store:store)
        XCTAssertNotNil(try snapshots.loadSnapshot(), "precondition: A's snapshot is readable under E1")

        var delivered: CampusWidgetModel?
        CampusWidgetDelivery.deliverSnapshot(
            now:now,
            preview:false,
            snapshots:snapshots,
            vault:vault,
            commitLock:UnsharedLock(),
            lines:{ ReminderLines() },
            beforeVerify:{
                try? vault.saveSessionEpoch(SessionEpoch(id:"E2", phase:.switching))
            }
        ) { model in
            delivered = model
        }
        let face = try XCTUnwrap(delivered)
        XCTAssertFalse(showsPrevious(face), "getSnapshot completion must never deliver A's numbers after epoch switch")
        XCTAssertEqual(face.state, .never)
        XCTAssertNil(face.balance)
    }

    /// Revo #3 (`getSnapshot`): when the shared commit lock is unavailable, fail closed.
    func testDeliverSnapshotFailsClosedWhenCommitLockUnavailable() throws {
        let store = try seededActiveEpoch("E1")
        let vault = StoredSchoolVault(store:store)
        let snapshots = SharedSnapshotStore(store:store)
        XCTAssertNotNil(try snapshots.loadSnapshot(), "precondition: A's snapshot is readable under E1")

        var delivered: CampusWidgetModel?
        CampusWidgetDelivery.deliverSnapshot(
            now:now,
            preview:false,
            snapshots:snapshots,
            vault:vault,
            commitLock:FailingCommitLock(),
            lines:{ ReminderLines() }
        ) { model in
            delivered = model
        }
        let face = try XCTUnwrap(delivered)
        XCTAssertTrue(face.placeholder)
        XCTAssertFalse(showsPrevious(face), "placeholder skeleton must never carry A's balance")
    }

    /// Revo #3 (`getTimeline`): even after network refresh returned A's snapshot and the candidate
    /// timeline + reminder lines were constructed, an epoch transition before commit-lock
    /// verification discards A's numbers before invoking `completion`.
    func testDeliverTimelineDropsRefreshedCandidateWhenEpochChangesBeforeCommitLock() async throws {
        let store = try seededActiveEpoch("E1")
        let vault = StoredSchoolVault(store:store)
        let snapshots = SharedSnapshotStore(store:store)
        let refreshedA = try XCTUnwrap(try snapshots.loadSnapshot())

        let delivered = DeliveryBox<CampusWidgetPlan.Faces>()
        await CampusWidgetDelivery.deliverTimeline(
            now:now,
            interval:30 * 60,
            snapshots:snapshots,
            vault:vault,
            commitLock:UnsharedLock(),
            lines:{ ReminderLines() },
            finishPendingClear:{},
            refresh:{ _ in refreshedA },
            beforeVerify:{
                try? vault.saveSessionEpoch(SessionEpoch(id:"E2", phase:.signedOutPendingClear))
            }
        ) { plan in
            delivered.set(plan)
        }
        let plan = try XCTUnwrap(delivered.value)
        XCTAssertFalse(plan.faces.isEmpty, "timeline is never empty")
        XCTAssertFalse(plan.faces.contains { showsPrevious($0.model) },
                       "getTimeline completion must never deliver A's refreshed numbers after epoch change")
        XCTAssertEqual(plan.faces.first?.model.state, .never)
    }

    /// Revo #3 (`getTimeline`): when the shared commit lock is unavailable, deliver one safe
    /// placeholder entry with short retry.
    func testDeliverTimelineFailsClosedWhenCommitLockUnavailable() async throws {
        let store = try seededActiveEpoch("E1")
        let vault = StoredSchoolVault(store:store)
        let snapshots = SharedSnapshotStore(store:store)
        let refreshedA = try XCTUnwrap(try snapshots.loadSnapshot())

        let delivered = DeliveryBox<CampusWidgetPlan.Faces>()
        await CampusWidgetDelivery.deliverTimeline(
            now:now,
            interval:30 * 60,
            snapshots:snapshots,
            vault:vault,
            commitLock:FailingCommitLock(),
            lines:{ ReminderLines() },
            finishPendingClear:{},
            refresh:{ _ in refreshedA }
        ) { plan in
            delivered.set(plan)
        }
        let plan = try XCTUnwrap(delivered.value)
        XCTAssertEqual(plan.faces.count, 1)
        XCTAssertEqual(plan.faces.first?.model.placeholder, true)
        XCTAssertFalse(plan.faces.contains { showsPrevious($0.model) })
        XCTAssertEqual(plan.next, now.addingTimeInterval(WidgetStoredData.unreadableRetry))
    }
}
