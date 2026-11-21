//
//  SampleClockTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 「先看看示例」 on a phone outside China: home's 最近, 校园卡记录 and the shower page read the
/// sample shower on the phone's clock, and its day is the phone's.
@MainActor
final class SampleClockTests: XCTestCase {
    private var savedZone: TimeZone!

    override func setUp() { savedZone = NSTimeZone.default }
    override func tearDown() { NSTimeZone.default = savedZone }

    func testTheSampleReadsOnThePhonesClock() throws {
        for zone in ["America/Los_Angeles", "Asia/Shanghai"] {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier:zone))
            var phone = Calendar(identifier:.gregorian)
            phone.timeZone = .current
            let now = Date()
            let data = HomeData.sample(now:now)
            XCTAssertEqual(data.calendar.timeZone, TimeZone.current, zone)
            XCTAssertEqual(RecordsDemo.list.source.calendar.timeZone, TimeZone.current, zone)
            let ended = try XCTUnwrap(data.lastShowerEnded)
            let showers = data.recents.filter { $0.kind == .shower }
            XCTAssertEqual(showers.count, 1, zone)
            XCTAssertEqual(showers.first.map { CardDays.clock($0.date, calendar:data.calendar) },
                           CardDays.clock(ended, calendar:phone), "\(zone): 最近 and the shower page agree")
            XCTAssertTrue(data.recents.allSatisfy { $0.date <= now }, zone)
            let days = CardDays.groups(history:nil, app:data.appActivities, now:now, calendar:data.calendar)
            XCTAssertEqual(days.first?.items.first.map { phone.isDate($0.date, inSameDayAs:ended) }, true, zone)
        }
    }
}
