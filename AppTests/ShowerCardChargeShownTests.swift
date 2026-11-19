import XCTest
import Core
@testable import XiaoRiChang

/// 「校园卡已扣 ¥x」 where a kept or stopped shower is listed: 清爽's 待核对的热水记录 rows, 暖橙's
/// list and stopped page (through `ShowerCardRecords`). Synthetic records only.
@MainActor
final class ShowerCardChargeShownTests: XCTestCase {
    func testClearRowsShowTheMatchedCharge() {
        let now = Date()
        let start = now.addingTimeInterval(-7200)
        let data = HomeView.ShowerPageDemo.charging(HomeData.sample(now:now), started:start)
        let retained = ShowerRetainedSummary(records:[
            ShowerState(phase:.running, machineID:"11223344", startedAt:start, stateReviewRequired:true),
            ShowerState(phase:.failed, machineID:"11223344", startedAt:start.addingTimeInterval(600),
                        failure:ShowerFailure(reason:.settleUnconfirmed, needsReview:true)),
        ])
        let orders = ClearRecentOrders(data:data, laundry:LaundryFacts(), retained:retained, now:now)
        let lines = orders.retainedLines { _ in "T" }
        XCTAssertEqual(lines.map(\.charge), [nil, "校园卡已扣 ¥1.32"], "only the shower started that second")
        XCTAssertEqual(lines[1].spoken, "T，水控 11223344 · 停水未结算，校园卡已扣 1.32 元")

        let unread = ClearRecentOrders(data:HomeData(), laundry:LaundryFacts(), retained:retained, now:now)
        XCTAssertEqual(unread.retainedLines { _ in "T" }.map(\.charge), [nil, nil], "no card records: nothing")
    }

    func testWarmPagesMatchFromTheCardRecords() {
        let start = Date().addingTimeInterval(-3600)
        let data = HomeView.ShowerPageDemo.charging(HomeData.sample(), started:start)
        let records = ShowerCardRecords(records:data.snapshot.activity.value?.records)
        XCTAssertEqual(records.charge(started:start), Money(fen:132))
        XCTAssertNil(records.charge(started:start.addingTimeInterval(1)))
        XCTAssertNil(ShowerCardRecords().charge(started:start), "signed out: no records, nothing shown")
    }

    /// The kept demo: one of its showers charged, the others not.
    func testTheKeptDemoChargesOneShower() {
        let kept = HomeView.ShowerPageDemo.retained()
        let data = HomeView.ShowerPageDemo.charging(HomeData.sample(), started:HomeView.ShowerPageDemo.chargedStart(kept))
        let records = ShowerCardRecords(records:data.snapshot.activity.value?.records)
        XCTAssertEqual(kept.entries.map { records.charge(started:$0.started) }, [nil, nil, Money(fen:132)])
    }
}
