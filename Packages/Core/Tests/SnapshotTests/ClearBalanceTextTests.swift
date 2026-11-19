import XCTest
import Core

/// 清爽 home's 双余额 card: its words, two decimals, each column's own read time.
final class ClearBalanceTextTests: XCTestCase {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let posix = Locale(identifier: "en_US_POSIX")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func meter(money: String? = "25.56", daily: Decimal? = 4.6) -> Meter {
        Meter(comAddress: "M1", name: "3栋108", leftMoney: money.flatMap { Money(yuanString: $0) },
              remainingKWh: 42.6, dailyUseKWh: daily)
    }

    func testTitlesAndLinks() {
        XCTAssertEqual(ClearBalanceText.homeTitle, "校园生活")
        XCTAssertEqual(ClearBalanceText.title, "双余额")
        XCTAssertEqual(ClearBalanceText.powerTitle, "宿舍电量")
        XCTAssertEqual(ClearBalanceText.cardTitle, "校园卡")
        XCTAssertEqual(ClearBalanceText.cardCaption, "校园消费余额")
        XCTAssertEqual(ClearBalanceText.topUp, "校园充值 · 微信")
        XCTAssertEqual(ClearBalanceText.pullHint, "下拉刷新余额")
        XCTAssertEqual(ClearBalanceText.meterLink(bound: true), "电表设置")
        XCTAssertEqual(ClearBalanceText.meterLink(bound: false), "绑定电表")
    }

    func testRoomHasNoSpaces() {
        XCTAssertEqual(ClearBalanceText.room("3 栋 108"), "3栋108")
        XCTAssertNil(ClearBalanceText.room(nil))
        XCTAssertNil(ClearBalanceText.room(" "))
    }

    func testNumbersAlwaysHaveTwoPlaces() {
        XCTAssertEqual(ClearBalanceText.number(Decimal(string: "42.6")), "42.60")
        XCTAssertEqual(ClearBalanceText.number(Decimal(string: "86.5")), "86.50")
        XCTAssertEqual(ClearBalanceText.number(Decimal(string: "1234.5")), "1,234.50")
        XCTAssertEqual(ClearBalanceText.number(nil), "—")
    }

    func testPowerLines() {
        XCTAssertEqual(ClearBalanceText.powerMoney(meter()), "电费 ¥25.56")
        XCTAssertEqual(ClearBalanceText.powerMoney(meter(money: nil)), "电费 未获取")
        XCTAssertEqual(ClearBalanceText.powerMoney(nil), "电费 未获取")
        XCTAssertEqual(ClearBalanceText.yesterday(meter()), "昨日 4.60 度")
        XCTAssertEqual(ClearBalanceText.yesterday(meter(daily: nil)), "昨日 未返回")
    }

    func testEachColumnHasItsOwnReadTime() {
        var power = Tile<Meter>()
        XCTAssertNil(ClearBalanceText.powerStamp(power, now: now, locale: posix, timeZone: zone))
        power.succeed(meter(), at: now.addingTimeInterval(-60))
        let clock = ClearBalanceText.clock(now.addingTimeInterval(-60), locale: posix, timeZone: zone)
        XCTAssertEqual(ClearBalanceText.powerStamp(power, now: now, locale: posix, timeZone: zone), "查询 " + clock)
        // Older than 20 minutes, or a failed read after it: 「上次」.
        XCTAssertEqual(ClearBalanceText.powerStamp(power, now: now.addingTimeInterval(20 * 60 + 1), locale: posix, timeZone: zone),
                       "上次 " + clock)
        power.fail(.offline, at: now)
        XCTAssertEqual(ClearBalanceText.powerStamp(power, now: now, locale: posix, timeZone: zone), "上次 " + clock)

        var card = Tile<Money>()
        XCTAssertNil(ClearBalanceText.cardStamp(card, locale: posix, timeZone: zone))
        card.succeed(Money(fen: 8650), at: now)
        XCTAssertEqual(ClearBalanceText.cardStamp(card, locale: posix, timeZone: zone),
                       "查询 " + ClearBalanceText.clock(now, locale: posix, timeZone: zone))
    }

    func testCardFreshness() {
        var card = Tile<Money>()
        XCTAssertEqual(ClearBalanceText.cardFreshness(card, signedIn: false, refreshing: false, now: now), "待配置")
        XCTAssertEqual(ClearBalanceText.cardFreshness(card, signedIn: true, refreshing: false, now: now), "暂未获取")
        card.succeed(Money(fen: 8650), at: now)
        XCTAssertEqual(ClearBalanceText.cardFreshness(card, signedIn: true, refreshing: false, now: now), "已更新")
        XCTAssertEqual(ClearBalanceText.cardFreshness(card, signedIn: true, refreshing: true, now: now), "更新中")
        XCTAssertEqual(ClearBalanceText.cardFreshness(card, signedIn: true, refreshing: false, now: now.addingTimeInterval(3600)),
                       "上次余额")
    }

    func testIssuesListTheCardThenTheMeter() {
        var s = HomeSnapshot()
        XCTAssertEqual(ClearBalanceText.issues(s, signedIn: true, meterBound: true), [])
        s.card.fail(.offline, at: now)
        s.power.fail(.timedOut, at: now)
        XCTAssertEqual(ClearBalanceText.issues(s, signedIn: true, meterBound: true),
                       [ServiceError.offline.userMessage, "电费：" + ServiceError.timedOut.userMessage])
        XCTAssertEqual(ClearBalanceText.issues(s, signedIn: true, meterBound: false), [ServiceError.offline.userMessage])
        XCTAssertEqual(ClearBalanceText.issues(s, signedIn: false, meterBound: true), [])
    }

    func testCurrencyFollowsTheSystem() {
        XCTAssertEqual(ClearBalanceText.currency(Decimal(string: "1.32")!, locale: Locale(identifier: "zh_CN")), "¥1.32")
        XCTAssertEqual(ClearBalanceText.currency(Decimal(string: "1.32")!, locale: Locale(identifier: "en_US")), "CN¥1.32")
    }
}
