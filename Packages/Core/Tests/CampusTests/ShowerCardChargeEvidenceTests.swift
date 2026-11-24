//
//  ShowerCardChargeEvidenceTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
@testable import Core

/// A shower's charge is shown only when home's read of the card's records holds every record that
/// could be it. The school pages its bills by count, newest first, and home reads one page: a
/// page cut inside the shower's day may leave a second payment of that second on the next page.
/// A page cut short, one missing, a row read twice, or a charge not booked yet shows nothing; it
/// is never guessed. Synthetic bills only.
final class ShowerCardChargeEvidenceTests: XCTestCase {
    let calendar = SchoolCalendar.shanghai
    let pageSize = CardActivity.pageSize

    /// 2026-11-02 17:49:39 in the school's calendar, with the phone's fraction of a second.
    var start: Date {
        calendar.date(from:DateComponents(year:2026, month:11, day:2, hour:17, minute:49, second:39))!.addingTimeInterval(0.62)
    }

    func shower(_ time: String = "174939", fen: Int = 132, date: String = "20261102", balance: Int = 5000) -> CardRecord {
        CardRecord(date:date, time:time, title:"蓝牙热水", amount:Money(fen:fen), balanceAfter:Money(fen:balance), direction:"1")
    }

    /// `count` meals on `date`, newest first, all later in the day than the shower.
    func meals(_ count: Int, date: String = "20261102") -> [CardRecord] {
        (0..<count).map { i in
            let second = 86_399 - i
            let time = String(format:"%02d%02d%02d", second / 3600, second / 60 % 60, second % 60)
            return CardRecord(date:date, time:time, title:"POS消费(示例饭堂POS)", amount:Money(fen:850),
                              balanceAfter:Money(fen:9000 - i), direction:"1")
        }
    }

    /// Home's read of one page of the school's answer.
    func read(_ rows: [CardRecord], total: Int?) -> CardActivity {
        CardActivity(page:CardRecordPage(total:total, rows:rows), begin:"20261027", end:"20261102", pageSize:pageSize)
    }

    func shown(_ activity: CardActivity?) -> Money? {
        ShowerCardCharge.amount(started:start, activity:activity, calendar:calendar)
    }

    /// The whole bill on one page: the one payment of that second is shown.
    func testACompleteReadShowsTheCharge() {
        let activity = read(meals(3) + [shower()], total:4)
        XCTAssertTrue(activity.complete)
        XCTAssertEqual(shown(activity), Money(fen:132))
    }

    /// Two payments in that second, the first the last row of page 1 and the second the first of
    /// page 2. Home holds page 1 only: nothing is shown, though page 1 has exactly one match.
    func testTwoChargesInOneSecondSplitAcrossPagesShowNothing() {
        let page1 = meals(pageSize - 1) + [shower(fen:132, balance:4000)]
        let page2 = [shower(fen:201, balance:3799)] + meals(2, date:"20261101")
        XCTAssertEqual(ShowerCardCharge.amount(started:start, records:page1, calendar:calendar), Money(fen:132),
                       "page 1 alone has one match")
        XCTAssertNil(shown(read(page1, total:page1.count + page2.count)), "the school says more are on page 2")
        XCTAssertNil(shown(read(page1, total:nil)), "a full page without a total may have more after it")
        // Both pages together: two in that second can't be told apart.
        XCTAssertNil(ShowerCardCharge.amount(started:start, records:page1 + page2, calendar:calendar))
    }

    /// Page 2 never came (the read is one page): the shower's day is not read to its end.
    func testAMissingNextPageShowsNothing() {
        let page1 = meals(pageSize - 1) + [shower()]
        XCTAssertFalse(read(page1, total:pageSize + 7).complete)
        XCTAssertNil(shown(read(page1, total:pageSize + 7)))
        // A page shorter than the total says (rows left out): still not shown.
        XCTAssertNil(shown(read(meals(10) + [shower()], total:pageSize + 7)))
    }

    /// The same payment read twice (a page moved under the list): two rows of that second.
    func testADuplicatedRowShowsNothing() {
        XCTAssertNil(shown(read(meals(2) + [shower(), shower()], total:4)))
        XCTAssertNil(shown(read(meals(2) + [shower(), shower()], total:nil)))
    }

    /// The school books a shower about an hour later: a read before shows nothing; the read after
    /// shows it only when it holds the whole day.
    func testALateChargeShowsOnlyOnceItIsReadInFull() {
        XCTAssertNil(shown(read(meals(3), total:3)), "not booked yet")
        XCTAssertEqual(shown(read(meals(3) + [shower()], total:4)), Money(fen:132), "booked, whole day read")
        // Booked, and new payments of the day pushed the page full: whether a second one of that
        // second sits on page 2 is unknown.
        let pushed = meals(pageSize - 1) + [shower()]
        XCTAssertNil(shown(read(pushed, total:pageSize + 1)))
    }

    /// A page cut short on an older day still holds the whole shower's day: shown.
    func testACutOnAnOlderDayStillShowsTheCharge() {
        let page = meals(10) + [shower()] + meals(pageSize - 11, date:"20261101")
        let activity = read(page, total:pageSize + 20)
        XCTAssertFalse(activity.complete)
        XCTAssertEqual(shown(activity), Money(fen:132))
    }

    func testNoReadShowsNothing() {
        XCTAssertNil(shown(nil))
        XCTAssertNil(ShowerCardCharge.amount(started:nil, activity:read([shower()], total:1), calendar:calendar))
    }
}
