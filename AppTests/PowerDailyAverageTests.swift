//
//  PowerDailyAverageTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 10: what the app shows from `preUseDay` outside home's days line. `preUseDay` is the school's
/// days-left estimate, so these show the daily average behind it (remaining ÷ days), never the
/// days as 度, and nothing when the estimate can't be used.
@MainActor
final class PowerDailyAverageTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier:.gregorian)
        c.timeZone = TimeZone(identifier:"Asia/Shanghai")!
        return c
    }()
    var now: Date { calendar.date(from:DateComponents(year:2026, month:11, day:10, hour:9, minute:15))! }

    func meter(kwh: Decimal = 42.6, days: Decimal? = 9.26) -> Meter {
        Meter(comAddress:"M1", name:"3栋108", leftMoney:Money(yuanString:"23.40"), remainingKWh:kwh, estimatedDaysLeft:days)
    }

    func snapshot(_ meter: Meter) -> HomeSnapshot {
        var s = HomeSnapshot(checkedAt:now)
        s.card.succeed(Money(yuanString:"86.50")!, at:now)
        s.power.succeed(meter, at:now)
        return s
    }

    func testTheWidgetModelCarriesTheDailyAverage() {
        let model = CampusWidgetModel(snapshot:snapshot(meter()), account:SchoolAccount(account:"99100991"), now:now)
        XCTAssertEqual(model.dailyAverageKWh.map(CampusFormat.kwh), "4.6")
        let none = CampusWidgetModel(snapshot:snapshot(meter(days:0)), account:SchoolAccount(account:"99100991"), now:now)
        XCTAssertNil(none.dailyAverageKWh)
    }

    func testWarmWidgetLine() {
        XCTAssertEqual(CampusFormat.dailyAverageLabel, "每天约用")
        XCTAssertEqual(CampusWidgetFace.dailyAverageLine(Decimal(string:"11.33")), "每天约用 11.3 度")
        XCTAssertNil(CampusWidgetFace.dailyAverageLine(nil))
    }

    func testClearWidgetLine() {
        XCTAssertEqual(ClearScriptsFace.dailyAverageRow(Decimal(string:"11.333")).value, "约 11.33 度")
        XCTAssertEqual(ClearScriptsFace.dailyAverageRow(Decimal(string:"11.333")).label, "日均")
        XCTAssertEqual(ClearScriptsFace.dailyAverageRow(nil).value, "未返回")
        XCTAssertEqual(ClearScriptsFace.dailyAverageRow(nil).label, "日均")
    }

    func testSamplePageShowsTheAverageUnderTheSameLabel() {
        XCTAssertEqual(SamplePowerPage.dailyUse(meter()), "4.6 度")
        XCTAssertEqual(SamplePowerPage.dailyUse(meter(days:nil)), "—")
        XCTAssertEqual(SamplePowerPage.dailyUse(nil), "—")
    }
}
