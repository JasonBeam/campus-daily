//
//  ShowerCardChargeShownTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

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
        let records = ShowerCardRecords(activity:data.snapshot.activity.value, calendar:data.calendar)
        XCTAssertEqual(records.charge(started:start), Money(fen:132))
        XCTAssertNil(records.charge(started:start.addingTimeInterval(1)))
        XCTAssertNil(ShowerCardRecords().charge(started:start), "signed out: no records, nothing shown")
    }

    /// Home's read is one page cut inside the shower's day (the school has more rows for it): a
    /// second payment of that second may be on the next page, so neither theme shows a charge.
    func testAReadCutInsideTheShowersDayShowsNothing() throws {
        let now = Date()
        let start = now.addingTimeInterval(-7200)
        var data = HomeView.ShowerPageDemo.charging(HomeData.sample(now:now), started:start)
        var activity = try XCTUnwrap(data.snapshot.activity.value)
        let day = SchoolCalendar.dayString(start, calendar:data.calendar)
        activity.records = activity.records.filter { $0.date >= day }
        activity.complete = false
        data.snapshot.activity.succeed(activity, at:data.snapshot.activity.fetchedAt ?? now)
        XCTAssertEqual(ShowerCardCharge.amount(started:start, activity:activity, calendar:data.calendar), nil)

        XCTAssertNil(ShowerCardRecords(activity:data.snapshot.activity.value, calendar:data.calendar).charge(started:start))
        let retained = ShowerRetainedSummary(records:[
            ShowerState(phase:.failed, machineID:"11223344", startedAt:start,
                        failure:ShowerFailure(reason:.settleUnconfirmed, needsReview:true)),
        ])
        let orders = ClearRecentOrders(data:data, laundry:LaundryFacts(), retained:retained, now:now)
        XCTAssertEqual(orders.retainedLines { _ in "T" }.map(\.charge), [nil])

        activity.complete = true
        data.snapshot.activity.succeed(activity, at:data.snapshot.activity.fetchedAt ?? now)
        XCTAssertEqual(ShowerCardRecords(activity:data.snapshot.activity.value, calendar:data.calendar).charge(started:start),
                       Money(fen:132), "the same rows, read in full")
    }

    /// The kept demo: one of its showers charged, the others not.
    func testTheKeptDemoChargesOneShower() {
        let kept = HomeView.ShowerPageDemo.retained()
        let data = HomeView.ShowerPageDemo.charging(HomeData.sample(), started:HomeView.ShowerPageDemo.chargedStart(kept))
        let records = ShowerCardRecords(activity:data.snapshot.activity.value, calendar:data.calendar)
        XCTAssertEqual(kept.entries.map { records.charge(started:$0.started) }, [nil, nil, Money(fen:132)])
    }
}
