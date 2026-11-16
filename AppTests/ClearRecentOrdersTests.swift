import XCTest
import Core
@testable import XiaoRiChang

/// The 订单 tab's own sections above the card's days: the laundry order, the open shower and
/// the last settled shower, in that order, each only when there is one.
@MainActor
final class ClearRecentOrdersTests: XCTestCase {
    func testTabAndSectionWords() {
        XCTAssertEqual(ClearRecentOrders.tabTitle, "订单")
        XCTAssertEqual(ClearRecentOrders.title, "最近订单")
        XCTAssertEqual(ClearRecentOrders.laundryTitle, "最近洗衣订单")
        XCTAssertEqual(ClearRecentOrders.showerOpenTitle, "当前热水记录")
        XCTAssertEqual(ClearRecentOrders.showerSettledTitle, "最近热水结算")
        XCTAssertEqual(ClearRecentOrders.settled, "热水已结算")
        XCTAssertEqual(ClearRecentOrders.noAmount, "金额未返回")
    }

    func testTheSampleShowsTheLastSettledShowerOnly() {
        let now = Date()
        let orders = ClearRecentOrders(data:HomeData.sample(now:now), laundry:LaundryFacts(), now:now)
        XCTAssertNil(orders.laundry)
        XCTAssertNil(orders.showerOpen)
        let settled = try! XCTUnwrap(orders.showerSettled)
        XCTAssertEqual(settled.amount, SampleData.lastShowerCost.yuan)
        XCTAssertEqual(orders.sections, [.showerSettled])
    }

    func testAnOpenOrderAndShowerComeFirst() {
        let now = Date()
        var data = HomeData.sample(now:now)
        data.shower = .showering(now.addingTimeInterval(-60))
        let orders = ClearRecentOrders(data:data, laundry:LaundryDemo.make(.run, now:now).facts, now:now)
        XCTAssertEqual(orders.laundry, .init(title:"洗衣中", program:"标准洗", amount:Decimal(string:"4")))
        XCTAssertEqual(orders.showerOpen?.title, "热水洗澡")
        XCTAssertEqual(orders.sections, [.laundry, .showerOpen, .showerSettled])
    }

    func testAFinishedOrderStaysAsTheLastOne() {
        let now = Date()
        let orders = ClearRecentOrders(data:HomeData.sample(now:now), laundry:LaundryDemo.make(.done, now:now).facts, now:now)
        XCTAssertEqual(orders.laundry?.title, "洗衣完成")
    }

    /// Showers a next use kept: their own section after the others, one row each, read-only.
    func testRetainedSectionListsEach() {
        let now = Date()
        let t0 = now.addingTimeInterval(-7200)
        let retained = ShowerRetainedSummary(records:[
            ShowerState(phase:.running, machineID:"11223344", startedAt:t0, stateReviewRequired:true),
            ShowerState(phase:.failed, machineID:"11223344", startedAt:t0.addingTimeInterval(600),
                        failure:ShowerFailure(reason:.settleUnconfirmed, needsReview:true)),
        ])
        let orders = ClearRecentOrders(data:HomeData.sample(now:now), laundry:LaundryFacts(), retained:retained, now:now)
        XCTAssertEqual(orders.sections, [.showerSettled, .showerRetained])
        let rows = orders.retainedRows { _ in "T" }
        XCTAssertEqual(rows, ["T · 11223344 · 停水未结算", "T · 11223344 · 结算未确认"])
        XCTAssertEqual(ClearRecentOrders.retainedTitle, "待核对的热水记录")
        XCTAssertEqual(ClearRecentOrders.retainedFooter, "可在学校官方热水消费明细中核对。")

        let none = ClearRecentOrders(data:HomeData.sample(now:now), laundry:LaundryFacts(), retained:nil, now:now)
        XCTAssertEqual(none.sections, [.showerSettled], "nothing kept or unreadable: no section")
    }

    func testNoLaundryWhileSchoolLaundryIsOff() {
        let now = Date()
        var data = HomeData.sample(now:now)
        data.laundryEnabled = false
        XCTAssertNil(ClearRecentOrders(data:data, laundry:LaundryDemo.make(.run, now:now).facts, now:now).laundry)
    }
}
