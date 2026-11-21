//
//  ClearRecentOrdersTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/10.
//

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
        let rows = orders.retainedLines { _ in "T" }
        XCTAssertEqual(rows, [.init(title:"T", detail:"水控 11223344 · 结算未确认"), .init(title:"T", detail:"水控 11223344 · 停水未结算")], "newest first")
        XCTAssertEqual(ClearRecentOrders.retainedTitle, "待核对的热水记录")
        XCTAssertEqual(ClearRecentOrders.retainedFooter, "可在校园卡消费明细中核对，扣费约 1 小时后入账。")

        let none = ClearRecentOrders(data:HomeData.sample(now:now), laundry:LaundryFacts(), retained:nil, now:now)
        XCTAssertEqual(none.sections, [.showerSettled], "nothing kept or unreadable: no section")
    }

    /// The kept showers' start times read as 上次热水 and home: 「今天 10:00」, 「昨天 …」, 「11月18日 08:41」.
    func testRetainedTimesReadAsHome() {
        let probe = ClearRecentOrders(data:HomeData.sample(now:Date()), laundry:LaundryFacts(), now:Date())
        let calendar = probe.calendar
        let now = calendar.date(from:DateComponents(year:2026, month:11, day:20, hour:12))!
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from:DateComponents(year:2026, month:11, day:day, hour:hour, minute:minute))!
        }
        let retained = ShowerRetainedSummary(records:[
            ShowerState(phase:.running, machineID:"11223344", startedAt:at(18, 8, 41), stateReviewRequired:true),
            ShowerState(phase:.running, machineID:"11223344", startedAt:at(19, 21, 5), stateReviewRequired:true),
            ShowerState(phase:.running, machineID:"11223344", startedAt:at(20, 10, 0), stateReviewRequired:true),
        ])
        let orders = ClearRecentOrders(data:HomeData.sample(now:now), laundry:LaundryFacts(), retained:retained, now:now)
        XCTAssertEqual(orders.retainedLines(now:now).map(\.title), ["今天 10:00", "昨天 21:05", "11月18日 08:41"])
    }

    func testNoLaundryWhileSchoolLaundryIsOff() {
        let now = Date()
        var data = HomeData.sample(now:now)
        data.laundryEnabled = false
        XCTAssertNil(ClearRecentOrders(data:data, laundry:LaundryDemo.make(.run, now:now).facts, now:now).laundry)
    }

    /// Two lines each, newest first; a shower that never started leads with its reason.
    func testRetainedLinesNewestFirst() {
        let now = Date()
        let t0 = now.addingTimeInterval(-7200)
        let retained = ShowerRetainedSummary(records:[
            ShowerState(phase:.running, machineID:"11223344", startedAt:t0, stateReviewRequired:true),
            ShowerState(phase:.failed, machineID:"11223344", failure:ShowerFailure(reason:.authorizeUncertain, needsReview:true)),
            ShowerState(phase:.failed, machineID:"AABBCCDD", startedAt:t0.addingTimeInterval(600),
                        failure:ShowerFailure(reason:.closeUnconfirmed, needsReview:true)),
        ])
        let orders = ClearRecentOrders(data:HomeData.sample(now:now), laundry:LaundryFacts(), retained:retained, now:now)
        let lines = orders.retainedLines { $0 == t0 ? "early" : "late" }
        XCTAssertEqual(lines, [.init(title:"late", detail:"水控 AABBCCDD · 关水未确认"),
                               .init(title:"early", detail:"水控 11223344 · 停水未结算"),
                               .init(title:"授权未确认", detail:"水控 11223344")])
    }

    /// Rows on the dorm's own controller leave it out; a record that never started has no
    /// second line then.
    func testRetainedLinesLeaveOutTheDormsController() {
        let now = Date()
        let t0 = now.addingTimeInterval(-7200)
        let retained = ShowerRetainedSummary(records:[
            ShowerState(phase:.running, machineID:"11223344", startedAt:t0, stateReviewRequired:true),
            ShowerState(phase:.failed, machineID:"11223344", failure:ShowerFailure(reason:.authorizeUncertain, needsReview:true)),
            ShowerState(phase:.failed, machineID:"AABBCCDD", startedAt:t0.addingTimeInterval(600),
                        failure:ShowerFailure(reason:.closeUnconfirmed, needsReview:true)),
        ], currentMachine:"11223344")
        let orders = ClearRecentOrders(data:HomeData.sample(now:now), laundry:LaundryFacts(), retained:retained, now:now)
        XCTAssertEqual(orders.retainedLines { $0 == t0 ? "early" : "late" },
                       [.init(title:"late", detail:"水控 AABBCCDD · 关水未确认"),
                        .init(title:"early", detail:"停水未结算"),
                        .init(title:"授权未确认", detail:nil)])
    }

    /// The hot-water page's kept line opens 订单 at its section.
    func testTheKeptLineOpensOrdersAtItsSection() {
        let navigator = ClearNavigator()
        navigator.homePath = [.shower]
        navigator.recordsPath = [.shower]
        navigator.showRetained(from:.homeButton)
        XCTAssertEqual(navigator.tab, .records)
        XCTAssertEqual(navigator.recordsPath, [])
        XCTAssertEqual(navigator.recordsScroll, .showerRetained)
        XCTAssertEqual(ClearRecentOrders.scrollID(.showerRetained), "recordsRetainedShowers")
    }
}
