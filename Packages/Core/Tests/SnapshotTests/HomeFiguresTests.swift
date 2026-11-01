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

    func snapshot(balance: String? = "86.50", kwh: Decimal? = 42.6, daily: Decimal? = 4.5,
                  readAt: Date? = nil, records: [CardRecord]? = nil) -> HomeSnapshot {
        var s = HomeSnapshot()
        if let balance { s.card.succeed(Money(yuanString: balance)!, at: readAt ?? now) }
        s.power.succeed(Meter(comAddress: "M1", name: "3栋108", remainingKWh: kwh, dailyUseKWh: daily), at: readAt ?? now)
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
        let f = power(snapshot(kwh: 42.6, daily: 4.5))
        XCTAssertEqual(f, HomeFigure(value: 42.6, low: false, subline: .lastsDays(9)))
        XCTAssertEqual(f.subline?.text, "够用约 9 天")
    }

    func testPowerWithoutPreviousDayHidesTheSubline() {
        XCTAssertEqual(power(snapshot(kwh: 42.6, daily: nil)), HomeFigure(value: 42.6, low: false, subline: nil))
        XCTAssertEqual(power(snapshot(kwh: 42.6, daily: 0)), HomeFigure(value: 42.6, low: false, subline: nil))
    }

    func testPowerUnderTheLineIsLowEvenWithManyDays() {
        let f = power(snapshot(kwh: 9.9, daily: 0.5))
        XCTAssertEqual(f, HomeFigure(value: 9.9, low: true, subline: .lastsDays(19)))
    }

    func testPowerUnderTheLineWithoutEstimateIsLowWithNoSubline() {
        XCTAssertEqual(power(snapshot(kwh: 3, daily: nil)), HomeFigure(value: 3, low: true, subline: nil))
    }

    func testPowerAtTheLineIsNotLow() {
        XCTAssertFalse(power(snapshot(kwh: 10, daily: nil)).low)
    }

    func testPowerOneDayLeftAboveTheLineIsLowUntilTomorrowNight() {
        // 09:15 + 1.5 days = tomorrow 21:15.
        let f = power(snapshot(kwh: 30, daily: 20))
        XCTAssertEqual(f, HomeFigure(value: 30, low: true, subline: .lastsUntil(.tomorrow)))
        XCTAssertEqual(f.subline?.text, "只够到明晚")
    }

    func testPowerRunningOutTodayIsTonight() {
        let f = power(snapshot(kwh: 12, daily: 24))
        XCTAssertEqual(f.subline, .lastsUntil(.tonight))
        XCTAssertEqual(f.subline?.text, "只够到今晚")
    }

    func testPowerEstimateCountsFromTheReading() {
        // Read two days ago with 1.9 days left: already past, tonight.
        let old = snapshot(kwh: 19, daily: 10, readAt: date(10, 28, 9))
        XCTAssertEqual(power(old).subline, .lastsUntil(.tonight))
    }

    /// Read two days ago with 3 days left: one day is left now, so it is red and says tomorrow
    /// night, not 「够用约 3 天」.
    func testPowerDaysLeftCountFromNow() {
        let old = snapshot(kwh: 30, daily: 10, readAt: date(10, 28, 9, 15))
        XCTAssertEqual(power(old), HomeFigure(value: 30, low: true, subline: .lastsUntil(.tomorrow)))
        let older = snapshot(kwh: 60, daily: 10, readAt: date(10, 28, 9, 15))
        XCTAssertEqual(power(older), HomeFigure(value: 60, low: false, subline: .lastsDays(4)))
    }

    func testPowerTwoDaysIsNotLow() {
        XCTAssertEqual(power(snapshot(kwh: 40, daily: 20)), HomeFigure(value: 40, low: false, subline: .lastsDays(2)))
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
