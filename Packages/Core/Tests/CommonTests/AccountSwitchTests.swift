import XCTest
@testable import Core
import CoreTestSupport

/// Someone else signed in: the previous person's numbers and hot-water binding go, unless a
/// shower may still need the binding.
final class AccountSwitchTests: XCTestCase {
    struct Failed: Error {}

    /// A confirmed switch and a login that couldn't tell the previous person say different things;
    /// the hot-water line and its button are the same for both. Unconfirmed with the dorm and
    /// meter kept, only a removed hot-water binding is worth an alert.
    func testTheNoticeWordingForEveryCase() throws {
        let switched = try XCTUnwrap(AccountSwitch.Notice(previousPersonUnconfirmed: false, dormAndMeterCleared: true, hotWaterCleared: false))
        XCTAssertEqual(switched.title, "换了账号，上一个账号的宿舍和电表已经清掉。")
        XCTAssertNil(switched.message)
        XCTAssertNil(switched.openHotWater)
        XCTAssertEqual(AccountSwitch.Notice(previousPersonUnconfirmed: false, dormAndMeterCleared: false, hotWaterCleared: false),
                       switched, "a confirmed switch always says so")
        let unconfirmed = try XCTUnwrap(AccountSwitch.Notice(previousPersonUnconfirmed: true, dormAndMeterCleared: true, hotWaterCleared: false))
        XCTAssertEqual(unconfirmed.title, "认不出是不是之前那个账号，宿舍和电表先清掉了，重新选一下。")
        XCTAssertNil(unconfirmed.message)
        XCTAssertNil(unconfirmed.openHotWater)
        for previousPersonUnconfirmed in [false, true] {
            let water = try XCTUnwrap(AccountSwitch.Notice(previousPersonUnconfirmed: previousPersonUnconfirmed,
                                                           dormAndMeterCleared: true, hotWaterCleared: true))
            XCTAssertEqual(water.title, previousPersonUnconfirmed ? unconfirmed.title : switched.title)
            XCTAssertEqual(water.message, "热水要重新设置。")
            XCTAssertEqual(water.openHotWater, "去设置热水")
        }

        XCTAssertNil(AccountSwitch.Notice(previousPersonUnconfirmed: true, dormAndMeterCleared: false, hotWaterCleared: false),
                     "nothing was cleared: no alert")
        let waterOnly = try XCTUnwrap(AccountSwitch.Notice(previousPersonUnconfirmed: true, dormAndMeterCleared: false, hotWaterCleared: true))
        XCTAssertEqual(waterOnly.title, "热水要重新设置。")
        XCTAssertNil(waterOnly.message)
        XCTAssertEqual(waterOnly.openHotWater, "去设置热水")
    }

    func testHotWaterForEveryCase() {
        var deleted = 0
        XCTAssertEqual(AccountSwitch.clearHotWater(hasBinding: false, mayClear: true) { deleted += 1 }, .none)
        XCTAssertEqual(AccountSwitch.clearHotWater(hasBinding: true, mayClear: true) { deleted += 1 }, .cleared)
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(AccountSwitch.clearHotWater(hasBinding: true, mayClear: false) { deleted += 1 }, .keptForReview)
        XCTAssertEqual(deleted, 1, "a shower that may still need the binding keeps it")
        XCTAssertEqual(AccountSwitch.clearHotWater(hasBinding: true, mayClear: true) { throw Failed() }, .keptForReview)
        XCTAssertEqual([AccountSwitch.HotWater.none, .cleared, .keptForReview].map(\.noticed), [false, true, true])
    }

    /// The real stores: after the switch the shared snapshot holds no balance and the binding is gone.
    func testTheSnapshotThenTheBindingAreCleared() async throws {
        let store = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: store)
        var old = HomeSnapshot(checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
        old.card.succeed(Money(fen: 100), at: Date(timeIntervalSince1970: 1_800_000_000))
        try snapshots.saveSnapshot(old)
        try store.write(Data("{}".utf8), for: .showerBinding)
        let stack = SchoolRefreshStack(store: store, http: URLSessionHTTPClient(allowedHosts: []), role: "app",
                                       leaseWait: 0, leaseFile: store.leaseFile, diagnostic: { _ in })
        var order: [String] = []
        let result = await AccountSwitch.clearPreviousPerson(
            snapshot: { order.append("snapshot"); try await stack.refresher.clear() },
            hotWater: {
                order.append("hotWater")
                return AccountSwitch.clearHotWater(hasBinding: (try? store.read(.showerBinding)) != nil, mayClear: true) {
                    try store.delete(.showerBinding)
                }
            })
        XCTAssertEqual(result, .cleared)
        XCTAssertEqual(order, ["snapshot", "hotWater"])
        XCTAssertNil(try snapshots.loadSnapshot()?.card.value)
        XCTAssertNil(try store.read(.showerBinding))
    }

    func testAFailedSnapshotWriteStillClearsHotWater() async {
        let result = await AccountSwitch.clearPreviousPerson(snapshot: { throw Failed() }, hotWater: { .cleared })
        XCTAssertEqual(result, .cleared)
    }
}
