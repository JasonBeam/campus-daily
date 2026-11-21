//
//  HomeRecentsDayTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
import UIKit
import Combine
import Core
@testable import XiaoRiChang

/// 暖橙 home's 「最近」 rows count 今天/昨天 from the clock home gives them, which moves on at a
/// day change (`DayChange`) and on coming back to the foreground.
final class HomeRecentsDayTests: XCTestCase {
    let cal = SchoolCalendar.shanghai

    func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testARowsDayMovesOnWithTheClock() {
        let item = RecentItem(id: "lunch", kind: .canteen, title: "食堂", date: moment(30, 12, 16), detail: "示例面馆",
                              amount: Money(fen: 1200), source: .card)
        XCTAssertEqual(RecentRow(item: item, now: moment(30, 23, 59)).subtitle, "今天 12:16 · 示例面馆")
        XCTAssertEqual(RecentRow(item: item, now: moment(31, 0, 0)).subtitle, "昨天 12:16 · 示例面馆")
        XCTAssertEqual(RecentRow(item: item, now: moment(32, 0, 0)).subtitle, "周五 12:16 · 示例面馆")
        XCTAssertEqual(RecentRow(item: item, now: moment(30, 23, 59)).spokenLabel, "食堂，今天 12:16 · 示例面馆，花了 12 元")
    }

    func testHomeListensForTheDayChange() {
        XCTAssertTrue(DayChange.names.contains(.NSCalendarDayChanged))
        XCTAssertTrue(DayChange.names.contains(UIApplication.significantTimeChangeNotification))
    }

    func testTheDayChangeReachesHomeOnTheMainQueue() {
        let heard = expectation(description: "day change")
        let watch = DayChange.publisher.sink {
            XCTAssertTrue(Thread.isMainThread)
            heard.fulfill()
        }
        DispatchQueue.global().async { NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil) }
        wait(for: [heard], timeout: 2)
        watch.cancel()
    }
}
