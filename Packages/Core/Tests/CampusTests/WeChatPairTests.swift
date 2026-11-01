import XCTest
@testable import Core
import CoreTestSupport

/// A canteen meal paid with WeChat comes as two records with one voucher, day, time and amount:
/// money in from WeChat (flag 「2」, 「微信支付」 in its name) and the canteen's payment (flag
/// 「1」). It is one canteen expense; a WeChat record without its other half is money in.
final class WeChatPairTests: XCTestCase {
    let cal = SchoolCalendar.shanghai
    /// 2026-10-30 12:00 in Shanghai.
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))! }

    func record(_ date: String, _ time: String, _ title: String = "POS消费示例面馆", _ yuan: String = "12.00",
                flag: String? = "1", voucher: String? = "next") -> CardRecord {
        vouchers += 1
        return CardRecord(date: date, time: time, title: title, amount: Money(yuanString: yuan)!, balanceAfter: nil,
                          direction: flag, voucher: voucher == "next" ? String(format: "997-%02d", vouchers) : voucher)
    }
    var vouchers = 0

    /// The two halves of a 16 元 meal at `time` (synthetic voucher 991…), the canteen's first.
    func pair(_ date: String = "20261030", _ time: String = "113000", inYuan: String = "16.00",
              voucher: String = "991-01") -> (out: CardRecord, in: CardRecord) {
        (record(date, time, "POS消费(示例饭堂POS)(示例饭堂POS)01档口示例面馆", "16.00", voucher: voucher),
         record(date, time, "微信支付(手机)", inYuan, flag: "2", voucher: voucher))
    }

    func history(_ pages: [[CardRecord]], total: Int? = nil) -> CardHistory {
        var h = CardHistory(now: noon)
        let all = total ?? pages.reduce(0) { $0 + $1.count }
        for rows in pages { h.receive(CardRecordPage(total: all, rows: rows), for: h.nextQuery!) }
        return h
    }

    /// `n` distinct canteen meals on `day` after 12:00, newest first.
    func meals(_ day: String, _ n: Int) -> [CardRecord] {
        (0..<n).map { i in record(day, String(format: "%02d%02d00", 20 - i / 60, 59 - i % 60)) }
    }

    // MARK: One expense

    func testAWeChatPaidMealIsOneCanteenExpense() {
        let p = pair()
        for rows in [[p.out, p.in], [p.in, p.out]] {
            let h = history([[record("20261030", "180000")] + rows + [record("20261029", "120000")]])
            let days = CardDays.groups(history: h, app: [], now: noon)
            XCTAssertEqual(days[0].items.count, 2)
            let meal = days[0].items[1]
            XCTAssertEqual(meal.kind, .canteen)
            XCTAssertEqual(meal.title, "食堂")
            XCTAssertEqual(meal.detail, "示例面馆 · 微信支付")
            XCTAssertEqual(meal.amountText, "−¥16.00")
            XCTAssertFalse(days[0].items.contains { $0.amountText?.hasPrefix("+") == true }, "no money-in row")
            XCTAssertEqual(days[0].total, Money(fen: 2800), "counted once, and the day keeps its total")
        }
    }

    /// The WeChat half may come with a negative amount: the same meal.
    func testANegativeWeChatHalfPairsToo() {
        let p = pair(inYuan: "-16.00")
        let h = history([[p.in, p.out]])
        let days = CardDays.groups(history: h, app: [], now: noon)
        XCTAssertEqual(days[0].items.map(\.amountText), ["−¥16.00"])
        XCTAssertEqual(days[0].total, Money(fen: 1600))
    }

    // MARK: Across a page boundary

    /// The WeChat half ends page 1, the canteen's half opens page 2: hidden and not counted
    /// until its partner comes, then one meal.
    func testAHalfWaitsForItsPartnerOnTheNextPage() {
        let p = pair("20261030", "113000")
        var h = CardHistory(now: noon)
        h.receive(CardRecordPage(total: 52, rows: meals("20261030", 49) + [p.in]), for: h.nextQuery!)
        var days = CardDays.groups(history: h, app: [], now: noon)
        XCTAssertEqual(days[0].items.count, 49, "the lone half is not shown yet")
        XCTAssertFalse(days[0].items.contains { $0.amountText?.hasPrefix("+") == true })
        XCTAssertNil(days[0].total)
        h.receive(CardRecordPage(total: 52, rows: [p.out, record("20261029", "090000")]), for: h.nextQuery!)
        days = CardDays.groups(history: h, app: [], now: noon)
        XCTAssertEqual(days[0].items.count, 50)
        XCTAssertEqual(days[0].items.last?.detail, "示例面馆 · 微信支付")
        XCTAssertEqual(days[0].total, Money(fen: 49 * 1200 + 1600))
    }

    /// The canteen's half ends page 1 and the WeChat half (same voucher, day, time and amount)
    /// opens page 2: it is the other half, not the same record read again.
    func testTheCanteenHalfFirstAndItsPartnerOnTheNextPage() {
        let p = pair("20261030", "113000")
        var h = CardHistory(now: noon)
        h.receive(CardRecordPage(total: 52, rows: meals("20261030", 49) + [p.out]), for: h.nextQuery!)
        h.receive(CardRecordPage(total: 52, rows: [p.in, record("20261029", "090000")]), for: h.nextQuery!)
        let days = CardDays.groups(history: h, app: [], now: noon)
        XCTAssertEqual(days[0].items.count, 50)
        XCTAssertEqual(days[0].items.last?.detail, "示例面馆 · 微信支付")
        XCTAssertEqual(days[0].items.last?.amountText, "−¥16.00")
        XCTAssertEqual(days[0].total, Money(fen: 49 * 1200 + 1600))
    }

    // MARK: Alone

    /// Once its day is read through, a WeChat record without a partner is money in, 「+¥」,
    /// never a canteen expense, and the day keeps its total.
    func testALoneHalfIsMoneyInOnceItsDayIsRead() {
        for name in ["微信支付(手机)", "POS消费(示例饭堂POS)示例面馆"] {
            let lone = record("20261030", "113000", name, "50.00", flag: "2")
            let h = history([[record("20261030", "180000"), lone, record("20261029", "120000")]])
            let days = CardDays.groups(history: h, app: [], now: noon)
            XCTAssertEqual(days[0].items.count, 2, name)
            let row = days[0].items[1]
            XCTAssertEqual(row.amountText, "+¥50.00", name)
            XCTAssertEqual(row.kind, .topUp, name)
            XCTAssertEqual(days[0].total, Money(fen: 1200), name)
        }
    }

    /// 「备付金充值(微信支付(手机))」 is a top-up, even beside a payment with its voucher.
    func testAWeChatTopUpIsNeverPaired() {
        let v = "991-09"
        let h = history([[record("20261030", "113000", "POS消费示例面馆", "50.00", voucher: v),
                          record("20261030", "113000", "备付金充值(微信支付(手机))", "50.00", flag: "2", voucher: v)]])
        let days = CardDays.groups(history: h, app: [], now: noon)
        XCTAssertEqual(days[0].items.map(\.amountText), ["−¥50.00", "+¥50.00"])
        XCTAssertEqual(days[0].total, Money(fen: 5000))
    }

    // MARK: Not a pair

    /// Two real meals alike in time, amount and place have their own vouchers: both stay.
    func testTwoIdenticalMealsAreNotMerged() {
        let h = history([[record("20261030", "113000", "POS消费示例面馆", "16.00"),
                          record("20261030", "113000", "POS消费示例面馆", "16.00")]])
        let days = CardDays.groups(history: h, app: [], now: noon)
        XCTAssertEqual(days[0].items.map(\.amountText), ["−¥16.00", "−¥16.00"])
        XCTAssertEqual(days[0].total, Money(fen: 3200))
    }

    func testOtherVouchersAmountsOrNamesAreNotMerged() {
        let out = record("20261030", "113000", "POS消费示例面馆", "16.00", voucher: "991-01")
        let otherVoucher = record("20261030", "113000", "微信支付(手机)", "16.00", flag: "2", voucher: "991-02")
        let otherAmount = record("20261030", "113000", "微信支付(手机)", "15.00", flag: "2", voucher: "991-01")
        let otherTime = record("20261030", "113100", "微信支付(手机)", "16.00", flag: "2", voucher: "991-01")
        for half in [otherVoucher, otherAmount, otherTime] {
            let days = CardDays.groups(history: history([[out, half]]), app: [], now: noon)
            XCTAssertEqual(days[0].items.count, 2)
            let meal = days[0].items.first { $0.kind == .canteen }
            XCTAssertEqual(meal?.detail, "示例面馆", "not tagged")
            XCTAssertEqual(meal?.amountText, "−¥16.00")
            XCTAssertEqual(days[0].items.first { $0.kind == .topUp }?.amountText?.hasPrefix("+¥"), true)
            XCTAssertEqual(days[0].total, Money(fen: 1600))
        }
        // Money in without 微信支付 in its name is not the other half; its direction is unknown.
        let plain = record("20261030", "113000", "示例超市", "16.00", flag: "2", voucher: "991-01")
        let days = CardDays.groups(history: history([[out, plain]]), app: [], now: noon)
        XCTAssertEqual(days[0].items.count, 2)
        XCTAssertNil(days[0].total)
    }

    // MARK: Home

    /// The home read pairs before the vouchers are dropped; the snapshot keeps the meal's tag.
    func testHomeCountsAWeChatMealOnceAndKeepsItsTag() throws {
        let p = pair("20261029", "113000")
        let page = CardRecordPage(total: 3, rows: [record("20261030", "080000"), p.out, p.in])
        let activity = CardActivity(page: page, begin: "20261028", end: "20261030", pageSize: CardActivity.pageSize)
        XCTAssertTrue(activity.complete)
        XCTAssertEqual(activity.records.count, 2)
        XCTAssertTrue(activity.records.allSatisfy { $0.voucher == nil })
        let stored = try JSONDecoder().decode(CardActivity.self, from: JSONEncoder().encode(activity))
        XCTAssertEqual(stored, activity)
        XCTAssertEqual(CardSpending.yesterday(Tile(value: stored, fetchedAt: noon), now: noon), Money(fen: 1600))
        let items = RecentFeed.items(card: stored.records, app: [], limit: 10)
        XCTAssertEqual(items.map(\.detail), ["示例面馆", "示例面馆 · 微信支付"])
        XCTAssertEqual(items[1].amountText, "−¥16.00")
    }

    /// A page cut short: a lone half on its oldest day may have its partner on the next page and
    /// is left out; one on a newer day is money in.
    func testHomeLeavesOutALoneHalfWhereThePageWasCut() {
        let newer = record("20261030", "090000", "微信支付(手机)", "50.00", flag: "2")
        let cut = record("20261029", "113000", "微信支付(手机)", "16.00", flag: "2")
        let page = CardRecordPage(total: 60, rows: [record("20261030", "100000"), newer, record("20261029", "120000"), cut])
        let activity = CardActivity(page: page, begin: "20261028", end: "20261030", pageSize: 4)
        XCTAssertFalse(activity.complete)
        XCTAssertEqual(activity.records.map(\.time), ["100000", "090000", "120000"])
        XCTAssertEqual(RecentFeed.items(card: activity.records, app: [], limit: 10)[1].amountText, "+¥50.00")
    }

    /// Records stored by an earlier build (without the tag) still read.
    func testARecordStoredWithoutTheTagStillReads() throws {
        let json = #"{"date":"20261030","time":"113000","title":"示例面馆","amount":{"fen":1600},"direction":"1"}"#
        let row = try JSONDecoder().decode(CardRecord.self, from: Data(json.utf8))
        XCTAssertFalse(row.paidWithWeChat)
    }

    /// The merged meal keeps no voucher in what is encoded or printed.
    func testAMergedMealNeverPrintsItsVoucher() throws {
        let p = pair()
        let merged = WeChatPairs.merged([p.out, p.in]) { _ in true }
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].paidWithWeChat)
        let json = String(decoding: try JSONEncoder().encode(merged[0]), as: UTF8.self)
        XCTAssertFalse(json.contains("991-01"))
        XCTAssertFalse(String(describing: merged).contains("991-01"))
    }
}
