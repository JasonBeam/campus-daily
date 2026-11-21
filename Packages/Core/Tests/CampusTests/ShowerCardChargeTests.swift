//
//  ShowerCardChargeTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core

/// A shower's charge on the campus card, read only: the one hot-water payment stamped with the
/// shower's start, to the second. Anything else (none, two, another kind) shows nothing.
final class ShowerCardChargeTests: XCTestCase {
    let calendar = SchoolCalendar.shanghai

    /// 2026-11-02 17:49:39 in the school's calendar, with the phone's fraction of a second.
    var start: Date {
        calendar.date(from:DateComponents(year:2026, month:11, day:2, hour:17, minute:49, second:39))!.addingTimeInterval(0.62)
    }

    func record(_ time: String, title: String = "蓝牙热水", fen: Int = 132, direction: String? = "1",
                date: String = "20261102") -> CardRecord {
        CardRecord(date:date, time:time, title:title, amount:Money(fen:fen), balanceAfter:Money(fen:5000), direction:direction)
    }

    func testTheSameSecondMatches() {
        let records = [record("120102", title:"POS消费(示例饭堂POS)", fen:850), record("174939")]
        XCTAssertEqual(ShowerCardCharge.amount(started:start, records:records), Money(fen:132))
    }

    func testOneSecondOffIsNoMatch() {
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:[record("174938")]))
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:[record("174940")]))
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:[record("174939", date:"20261101")]), "another day")
    }

    /// Two hot-water payments in that second can't be told apart: nothing is shown.
    func testTwoMatchesShowNothing() {
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:[record("174939"), record("174939", fen:201)]))
    }

    /// Only hot-water payments count: a meal or a top-up in that second is not the shower's.
    func testOtherRecordsAreIgnored() {
        let meal = record("174939", title:"POS消费(示例饭堂POS)", fen:850)
        let topUp = record("174939", title:"校园卡充值", fen:5000, direction:"2")
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:[meal, topUp]))
        XCTAssertEqual(ShowerCardCharge.amount(started:start, records:[meal, record("174939"), topUp]), Money(fen:132))
        let refund = record("174939", title:"蓝牙热水退款", fen:132, direction:"2")
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:[refund]), "money back is not a charge")
    }

    func testNoLedgerOrNoStartShowsNothing() {
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:nil))
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:[]))
        XCTAssertNil(ShowerCardCharge.amount(started:nil, records:[record("174939")]))
    }
}
