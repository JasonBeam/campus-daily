//
//  HomeFiguresTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import XCTest
@testable import Core

/// The two home numbers: when they turn red, which small line shows, and the update line.
final class HomeFiguresTests: XCTestCase {
    let calendar = UpdateTimeTextTests.shanghai
    let lines = ReminderLines(powerKWh: 10, cardYuan: 20)

    func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }
    var now: Date { date(10, 30, 9, 15) }

    func snapshot(balance: String? = "86.50", kwh: Decimal? = 42.6, days: Decimal? = 9.4,
                  readAt: Date? = nil, records: [CardRecord]? = nil) -> HomeSnapshot {
        var s = HomeSnapshot()
        if let balance { s.card.succeed(Money(yuanString: balance)!, at: readAt ?? now) }
        s.power.succeed(Meter(comAddress: "M1", name: "3栋108", remainingKWh: kwh, estimatedDaysLeft: days), at: readAt ?? now)
        if let records {
            s.activity.succeed(CardActivity(records: records, begin: "20261028", end: "20261030", complete: true), at: readAt ?? now)
        }
        return s
    }

    func record(_ date: String, _ time: String, _ title: String, _ yuan: String, flag: String? = "1") -> CardRecord {
        CardRecord(date: date, time: time, title: title, amount: Money(yuanString: yuan)!, balanceAfter: nil, direction: flag)
    }

    func power(_ s: HomeSnapshot) -> HomeFigure { HomeFigures.power(s, signedIn: true, lines: lines, now: now, calendar: calendar) }
    func card(_ s: HomeSnapshot) -> HomeFigure { HomeFigures.card(s, signedIn: true, lines: lines, now: now, calendar: calendar) }

    // MARK: 电量

    func testPowerLastsDaysRoundedDown() {
        let f = power(snapshot(kwh: 42.6, days: 9.4))
        XCTAssertEqual(f, HomeFigure(value: 42.6, low: false, subline: .lastsDays(9)))
        XCTAssertEqual(f.subline?.text, "够用约 9 天")
    }

    /// 6: no estimate, or one that can't be right (0, negative, over a year): no line rather
    /// than a wrong number.
    func testPowerWithoutAUsableEstimateHidesTheSubline() {
        for days: Decimal? in [nil, 0, -2, 365.1, 366, 9999] {
            XCTAssertEqual(power(snapshot(kwh: 42.6, days: days)), HomeFigure(value: 42.6, low: false, subline: nil), "\(String(describing: days))")
        }
        XCTAssertEqual(power(snapshot(kwh: 400, days: 365)).subline, .lastsDays(365))
    }

    func testPowerUnderTheLineIsLowEvenWithManyDays() {
        let f = power(snapshot(kwh: 9.9, days: 19.8))
        XCTAssertEqual(f, HomeFigure(value: 9.9, low: true, subline: .lastsDays(19)))
    }

    func testPowerUnderTheLineWithoutEstimateIsLowWithNoSubline() {
        XCTAssertEqual(power(snapshot(kwh: 3, days: nil)), HomeFigure(value: 3, low: true, subline: nil))
    }

    func testPowerAtTheLineIsNotLow() {
        XCTAssertFalse(power(snapshot(kwh: 10, days: nil)).low)
    }

    func testPowerOneDayLeftAboveTheLineIsLowUntilTomorrowNight() {
        // 09:15 + 1.5 days = tomorrow 21:15.
        let f = power(snapshot(kwh: 30, days: 1.5))
        XCTAssertEqual(f, HomeFigure(value: 30, low: true, subline: .lastsUntil(.tomorrow)))
        XCTAssertEqual(f.subline?.text, "只够到明晚")
    }

    func testPowerRunningOutTodayIsTonight() {
        let f = power(snapshot(kwh: 12, days: 0.5))
        XCTAssertEqual(f.subline, .lastsUntil(.tonight))
        XCTAssertEqual(f.subline?.text, "只够到今晚")
    }

    func testPowerEstimateCountsFromTheReading() {
        // Read two days ago with 1.9 days left: already past, tonight.
        let old = snapshot(kwh: 19, days: 1.9, readAt: date(10, 28, 9))
        XCTAssertEqual(power(old).subline, .lastsUntil(.tonight))
    }

    /// Read two days ago with 3 days left: one day is left now, so it is red and says tomorrow
    /// night, not 「够用约 3 天」.
    func testPowerDaysLeftCountFromNow() {
        let old = snapshot(kwh: 30, days: 3, readAt: date(10, 28, 9, 15))
        XCTAssertEqual(power(old), HomeFigure(value: 30, low: true, subline: .lastsUntil(.tomorrow)))
        let older = snapshot(kwh: 60, days: 6, readAt: date(10, 28, 9, 15))
        XCTAssertEqual(power(older), HomeFigure(value: 60, low: false, subline: .lastsDays(4)))
    }

    func testPowerTwoDaysIsNotLow() {
        XCTAssertEqual(power(snapshot(kwh: 40, days: 2)), HomeFigure(value: 40, low: false, subline: .lastsDays(2)))
    }

    // MARK: 电量 from the school's estimate (feedback 988405a3)

    /// 1: 13.6 度 the school says lasts 1.2 days, read now (09:15): out tomorrow ~14:00, red.
    func testPowerLowReadingFromTheFeedbackLastsUntilTomorrowNight() {
        let f = power(snapshot(kwh: 13.6, days: 1.2))
        XCTAssertEqual(f, HomeFigure(value: 13.6, low: true, subline: .lastsUntil(.tomorrow)))
        XCTAssertEqual(f.subline?.text, "只够到明晚")
    }

    /// 2: after the top-up, 182.5 度 for 16.1 days.
    func testPowerToppedUpReadingFromTheFeedbackLastsSixteenDays() {
        let f = power(snapshot(kwh: 182.5, days: 16.1))
        XCTAssertEqual(f, HomeFigure(value: 182.5, low: false, subline: .lastsDays(16)))
        XCTAssertEqual(f.subline?.text, "够用约 16 天")
    }

    /// 3: the same use (about 11.3 度 a day) before and after a top-up gives different days;
    /// 「够用约 11 天」 at both was the bug.
    func testPowerDaysFollowTheRemainingAtTheSameUse() {
        let before = power(snapshot(kwh: 13.6, days: 1.2)).subline
        let after = power(snapshot(kwh: 182.5, days: 16.1)).subline
        XCTAssertNotEqual(before, after)
        XCTAssertNotEqual(before, .lastsDays(11))
        XCTAssertNotEqual(after, .lastsDays(11))
    }

    /// 4: 0.3 days from 09:15 ends at about 16:30 today.
    func testPowerAFewHoursLeftIsTonight() {
        XCTAssertEqual(power(snapshot(kwh: 12, days: 0.3)), HomeFigure(value: 12, low: true, subline: .lastsUntil(.tonight)))
    }

    /// 5: the school's 3 days counted from a reading two days old: one day left, red.
    func testPowerEstimateFromAnOldReadingCountsFromTheReading() {
        let old = snapshot(kwh: 34, days: 3.0, readAt: date(10, 28, 9, 15))
        XCTAssertEqual(power(old), HomeFigure(value: 34, low: true, subline: .lastsUntil(.tomorrow)))
    }

    /// 7: nothing left and no estimate: red under the line, no days line.
    func testPowerNothingLeftWithoutEstimateIsLowWithNoSubline() {
        XCTAssertEqual(power(snapshot(kwh: 0, days: 0)), HomeFigure(value: 0, low: true, subline: nil))
    }

    /// Nothing left while the school still gives days: red, and no days line or night.
    func testPowerNothingLeftIgnoresTheSchoolsDays() {
        XCTAssertEqual(power(snapshot(kwh: 0, days: 3.2)), HomeFigure(value: 0, low: true, subline: nil))
        XCTAssertEqual(power(snapshot(kwh: 0, days: 1.2)), HomeFigure(value: 0, low: true, subline: nil))
        XCTAssertEqual(HomeFigures.power(snapshot(kwh: 0, days: 3.2), signedIn: true, lines: ReminderLines(powerKWh: 0, cardYuan: 20),
                                         now: now, calendar: calendar).low, true)
    }

    /// 8: under the line with many days left: red, and the days still say how long.
    func testPowerUnderTheLineKeepsTheSchoolsDays() {
        XCTAssertEqual(power(snapshot(kwh: 9.9, days: 19)), HomeFigure(value: 9.9, low: true, subline: .lastsDays(19)))
    }

    func testPowerNotReadIsADashWithNoLine() {
        var s = snapshot()
        s.power = Tile()
        XCTAssertEqual(power(s), HomeFigure(value: nil, low: false, subline: nil))
    }

    func testSignedOutShowsDashesAndAfterSignIn() {
        let s = snapshot(kwh: 1, records: [])
        for f in [HomeFigures.power(s, signedIn: false, lines: lines, now: now, calendar: calendar),
                  HomeFigures.card(s, signedIn: false, lines: lines, now: now, calendar: calendar)] {
            XCTAssertEqual(f, HomeFigure(value: nil, low: false, subline: .afterSignIn))
            XCTAssertEqual(f.subline?.text, "登录后显示")
        }
    }

    // MARK: 电量 without a meter

    func powerWith(_ meter: HomeFigure.MeterState, signedIn: Bool = true) -> HomeFigure {
        HomeFigures.power(snapshot(), signedIn: signedIn, meter: meter, lines: lines, now: now, calendar: calendar)
    }

    /// No meter bound: 「—」 with 「还没找到电表 · 去设置」 under it; the cell opens the meter page.
    func testNoMeterSaysSoAndOpensTheMeterPage() {
        let f = powerWith(.notFound)
        XCTAssertEqual(f, HomeFigure(value: nil, low: false, subline: .meterNotFound))
        XCTAssertEqual(f.subline?.text, "还没找到电表 · 去设置")
        XCTAssertEqual(f.spokenPower, "电量，还没找到电表，去设置")
        XCTAssertTrue(f.tappable)
    }

    /// The automatic lookup running: 「—」 with 「正在找电表…」 under it (a spinner beside), not tappable.
    func testFindingTheMeterSaysSoAndIsNotTappable() {
        let f = powerWith(.finding)
        XCTAssertEqual(f, HomeFigure(value: nil, low: false, subline: .findingMeter))
        XCTAssertEqual(f.subline?.text, "正在找电表…")
        XCTAssertEqual(f.spokenPower, "电量，正在找电表")
        XCTAssertFalse(f.tappable)
    }

    /// A bound meter shows its numbers as before; signed out is 「登录后显示」 whatever the meter.
    func testBoundAndSignedOutAreAsBefore() {
        XCTAssertEqual(powerWith(.bound), power(snapshot()))
        XCTAssertNil(powerWith(.bound).spokenPower, "the numbers are spoken by the cell")
        XCTAssertTrue(powerWith(.bound).tappable)
        for meter in [HomeFigure.MeterState.notFound, .finding] {
            XCTAssertEqual(powerWith(meter, signedIn: false), HomeFigure(value: nil, low: false, subline: .afterSignIn))
            XCTAssertTrue(powerWith(meter, signedIn: false).tappable)
        }
    }

    // MARK: 校园卡

    func testCardYesterdaySpent() {
        let f = card(snapshot(records: [record("20261029", "120500", "POS消费示例面馆", "12.00"),
                                        record("20261029", "180000", "校园卡充值", "50.00", flag: nil)]))
        XCTAssertEqual(f, HomeFigure(value: Decimal(string: "86.5"), low: false, subline: .spent(Money(fen: 1200))))
        XCTAssertEqual(f.subline?.text, "昨天花了 ¥12.00")
    }

    func testCardNothingSpentYesterday() {
        let f = card(snapshot(records: [record("20261030", "081000", "POS消费示例面馆", "5.00")]))
        XCTAssertEqual(f.subline?.text, "昨天没花钱")
    }

    func testCardRecordsUnreadableHideTheLine() {
        XCTAssertNil(card(snapshot(records: nil)).subline)
    }

    func testCardUnderTheLineIsLow() {
        XCTAssertTrue(card(snapshot(balance: "19.99")).low)
        XCTAssertFalse(card(snapshot(balance: "20.00")).low)
        XCTAssertFalse(card(snapshot(balance: nil)).low, "no value, never red")
    }

    // MARK: Update line

    func testUpdatedUsesTheOlderReading() {
        var s = snapshot()
        s.card.succeed(Money(fen: 1), at: date(10, 30, 9, 0))
        s.power.succeed(Meter(comAddress: "M1", name: "x", remainingKWh: 5), at: date(10, 30, 8, 10))
        let line = HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: false)
        XCTAssertEqual(line, .updated(date(10, 30, 8, 10)))
        XCTAssertEqual(line.text(now: now, calendar: calendar), "8:10 更新")
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: true, meterBound: false, refreshing: false), .updated(date(10, 30, 9, 0)))
    }

    func testFailedReadKeepsTheLastGoodTime() {
        var s = snapshot(readAt: date(10, 29, 22, 10))
        s.power.fail(.offline, at: now)
        let line = HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: false)
        XCTAssertEqual(line, .failed(lastGood: date(10, 29, 22, 10)))
        XCTAssertEqual(line.text(now: now, calendar: calendar), "没更新上，下拉再试 · 数字是 昨天 22:10 的")
    }

    func testUnboundMeterErrorIsNotAFailure() {
        var s = snapshot()
        s.power.fail(.offline, at: now)
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: true, meterBound: false, refreshing: false), .updated(now))
    }

    func testFailedWithNothingReadHasNoTime() {
        var s = HomeSnapshot()
        s.card.fail(.offline, at: now)
        let line = HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: false)
        XCTAssertEqual(line.text(now: now, calendar: calendar), "没更新上，下拉再试")
    }

    /// Reads that keep ending without storing their numbers leave the tiles without an error;
    /// the line says so instead of 「8:10 更新」, with the date when it is not today.
    func testNumbersNotSavingSayToReopenTheApp() {
        let s = snapshot(readAt: date(10, 30, 8, 10))
        let line = HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: false, notSaving: true)
        XCTAssertEqual(line, .notSaving(lastGood: date(10, 30, 8, 10)))
        XCTAssertEqual(line.text(now: now, calendar: calendar), "一直没更新上，重开 App 试试 · 数字是 8:10 的")
        let older = HomeUpdateLine.of(snapshot(readAt: date(10, 29, 22, 10)), signedIn: true, meterBound: true,
                                      refreshing: false, notSaving: true)
        XCTAssertEqual(older.text(now: now, calendar: calendar), "一直没更新上，重开 App 试试 · 数字是 昨天 22:10 的")
        XCTAssertEqual(HomeUpdateLine.of(HomeSnapshot(), signedIn: true, meterBound: true, refreshing: false, notSaving: true)
            .text(now: now, calendar: calendar), "一直没更新上，重开 App 试试")
    }

    /// Refreshing, a signed-out home, an expired login and a failed read all come first.
    func testNotSavingGivesWayToOtherLines() {
        var s = snapshot(readAt: date(10, 30, 8, 10))
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: true, notSaving: true), .refreshing)
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: false, meterBound: true, refreshing: false, notSaving: true), .hidden)
        s.card.fail(.offline, at: now)
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: false, notSaving: true),
                       .failed(lastGood: date(10, 30, 8, 10)))
        let expired = SchoolSnapshotReducer.reduce(snapshot(readAt: date(10, 30, 8, 10)), .sessionExpired(.sessionExpired(.ecykt), at: now))
        XCTAssertEqual(HomeUpdateLine.of(expired, signedIn: true, meterBound: true, refreshing: false, notSaving: true),
                       .expired(lastGood: date(10, 30, 8, 10)))
    }

    func testRefreshingWinsAndSignedOutHides() {
        var s = snapshot()
        s.card.fail(.offline, at: now)
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: true).text(now: now, calendar: calendar), "正在更新…")
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: false, meterBound: true, refreshing: true), .hidden)
        XCTAssertEqual(HomeUpdateLine.of(HomeSnapshot(), signedIn: true, meterBound: true, refreshing: false), .hidden)
    }

    /// The login ran out: the line says to sign in again (pulling again can't help).
    func testExpiredLoginSaysToSignInAgain() {
        let s = SchoolSnapshotReducer.reduce(snapshot(readAt: date(10, 30, 8, 10)), .sessionExpired(.sessionExpired(.ecykt), at: now))
        let line = HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: false)
        XCTAssertEqual(line, .expired(lastGood: date(10, 30, 8, 10)))
        XCTAssertEqual(line.text(now: now, calendar: calendar), "登录过期了，点这里重新登录 · 数字是 8:10 的")
        XCTAssertEqual(HomeUpdateLine.expired(lastGood: nil).text(now: now, calendar: calendar), "登录过期了，点这里重新登录")
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: true), .refreshing)
    }

    /// Holding off after a password login with no answer is not an expired login.
    func testHeldLoginIsStillTheFailedLine() {
        let s = SchoolSnapshotReducer.reduce(snapshot(readAt: date(10, 30, 8, 10)), .sessionExpired(.sessionExpired(.ecykt), at: now))
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: false, loginHeld: true),
                       .failed(lastGood: date(10, 30, 8, 10)))
    }

    /// A good read after the expiry clears it.
    func testLoginBackClearsTheExpiredLine() {
        var s = SchoolSnapshotReducer.reduce(snapshot(readAt: date(10, 30, 8, 10)), .sessionExpired(.sessionExpired(.ecykt), at: now))
        s = SchoolSnapshotReducer.reduce(s, .livenessOK(at: now))
        s = SchoolSnapshotReducer.reduce(s, .balance(.success(Money(fen: 100)), at: now))
        s = SchoolSnapshotReducer.reduce(s, .meter(.success(Meter(comAddress: "M1", name: "x", remainingKWh: 5)), at: now))
        XCTAssertEqual(HomeUpdateLine.of(s, signedIn: true, meterBound: true, refreshing: false), .updated(now))
    }

    func testExpiredLineOpensSettingsOnlyForAPausedSavedPassword() {
        XCTAssertEqual(HomeUpdateLine.signInTarget(nil), .signIn)
        XCTAssertEqual(HomeUpdateLine.signInTarget(SchoolAccount(account: "99100991")), .signIn)
        XCTAssertEqual(HomeUpdateLine.signInTarget(SchoolAccount(account: "99100991", password: "synthetic-pw-991")), .signIn)
        XCTAssertEqual(HomeUpdateLine.signInTarget(SchoolAccount(account: "99100991", password: "synthetic-pw-991", paused: true)), .account)
    }

    /// The age of the numbers is written as on the widget: the day and the clock once not today.
    func testNumbersTimeSaysTheDayAsTheWidgetDoes() {
        XCTAssertEqual(HomeUpdateLine.failed(lastGood: date(10, 26, 7, 5)).text(now: now, calendar: calendar),
                       "没更新上，下拉再试 · 数字是 10月26日 7:05 的")
        XCTAssertEqual(HomeUpdateLine.expired(lastGood: date(10, 29, 22, 10)).text(now: now, calendar: calendar),
                       "登录过期了，点这里重新登录 · 数字是 昨天 22:10 的")
        XCTAssertEqual(HomeUpdateLine.failed(lastGood: date(10, 26, 7, 5)).text(now: now, calendar: calendar),
                       "没更新上，下拉再试 · 数字是 " + UpdateTimeText.widgetUpdated(date(10, 26, 7, 5), now: now, calendar: calendar).replacingOccurrences(of: " 更新", with: "") + " 的")
    }

    func testStampOlderThanYesterdayIsTheDayOnly() {
        XCTAssertEqual(HomeUpdateLine.updated(date(10, 26, 7, 5)).text(now: now, calendar: calendar), "10月26日 更新")
        XCTAssertEqual(HomeUpdateLine.updated(date(10, 29, 7, 5)).text(now: now, calendar: calendar), "昨天 7:05 更新")
    }
}
