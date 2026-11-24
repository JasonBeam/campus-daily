//
//  ClearScriptsFaceTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/10.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 清爽's small widget draws the POWER / CARD face whenever it has numbers; signed out, waiting
/// for the first read, an expired login, the medium size and 暖橙 keep their own faces.
final class ClearScriptsFaceTests: XCTestCase {
    func model(_ state: WidgetFreshness, numbers: Bool = true) -> CampusWidgetModel {
        CampusWidgetModel(state: state, remainingKWh: numbers ? Decimal(string: "42.6") : nil,
                          balance: numbers ? Decimal(string: "86.5") : nil)
    }

    func testClearSmallWithNumbers() {
        XCTAssertTrue(ClearScriptsFace.draws(model(.fresh), medium: false, theme: .clear))
        XCTAssertTrue(ClearScriptsFace.draws(model(.stale), medium: false, theme: .clear))
    }

    func testOtherFacesKeepTheirOwn() {
        XCTAssertFalse(ClearScriptsFace.draws(model(.fresh), medium: false, theme: .warm), "暖橙")
        XCTAssertFalse(ClearScriptsFace.draws(model(.fresh), medium: true, theme: .clear), "medium")
        XCTAssertFalse(ClearScriptsFace.draws(model(.expired), medium: false, theme: .clear), "expired")
        XCTAssertFalse(ClearScriptsFace.draws(.never, medium: false, theme: .clear), "signed out")
        XCTAssertFalse(ClearScriptsFace.draws(model(.fresh, numbers: false), medium: false, theme: .clear), "first read")
        XCTAssertFalse(ClearScriptsFace.draws(.placeholderFace, medium: false, theme: .clear), "gallery placeholder")
    }

    /// The header's time is 24-hour like every other widget's, never 「早上7:41」 or 「7:41 PM」.
    func testHeaderTimeIsTwentyFourHour() {
        for identifier in ["zh_CN", "en_US", "ja_JP"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            calendar.locale = Locale(identifier: identifier)
            let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 7, minute: 41))!
            let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 19, minute: 5))!
            XCTAssertEqual(ClearScriptsFace.headerTime(morning, calendar: calendar), "7:41", identifier)
            XCTAssertEqual(ClearScriptsFace.headerTime(evening, calendar: calendar), "19:05", identifier)
            XCTAssertEqual(ClearScriptsFace.headerTime(evening, calendar: calendar),
                           UpdateTimeText.clock(evening, calendar: calendar), "the other widgets' clock")
        }
        XCTAssertEqual(ClearScriptsFace.headerTime(nil), "未更新")
    }
}
