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

        try StoredSchoolVault(store:store).markSnapshotStale(since:now)
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
        try StoredSchoolVault(store:store).markSnapshotStale(since:now)
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
}
