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

    func testNoLaundryWhileSchoolLaundryIsOff() {
        let now = Date()
        var data = HomeData.sample(now:now)
        data.laundryEnabled = false
        XCTAssertNil(ClearRecentOrders(data:data, laundry:LaundryDemo.make(.run, now:now).facts, now:now).laundry)
    }
}
