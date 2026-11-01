import XCTest
@testable import Core
import CoreTestSupport

/// 最近 and 昨天花了: short names, merchant names, one row per shower or order, the school's day.
final class RecentFeedTests: XCTestCase {
    let cal = SchoolCalendar.shanghai
    /// 2026-10-30 12:00 in Shanghai.
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))! }

    /// Payments carry flag 「1」; money coming in is given no flag here (`flag: nil`).
    func record(_ date: String, _ time: String, _ title: String, _ yuan: String, flag: String? = "1") -> CardRecord {
        CardRecord(date: date, time: time, title: title, amount: Money(yuanString: yuan)!, balanceAfter: nil, direction: flag)
    }

    func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: Short names

    func testRecordNamesMapToShortNames() {
        let cases: [(String, CardRecordKind)] = [
            ("蓝牙热水(中卡)(蓝牙热水(中卡))热水POS01(中卡)", .shower),
            ("POS消费(示例饭堂POS)(示例饭堂POS)01档口示例面馆", .canteen),
            ("示例食堂二楼", .canteen),
            ("校园卡充值", .topUp),
            ("银行圈存", .topUp),
            ("示例洗衣机", .laundry),
            ("购电(99栋)", .electricity),
            ("电费缴纳", .electricity),
            ("电费充值", .electricity),
            ("转入水控", .shower),
            ("示例超市", .other),
        ]
        for (name, kind) in cases { XCTAssertEqual(CardRecordKind.of(name: name), kind, name) }
        XCTAssertEqual(CardRecordKind.allCases.map(\.title), ["食堂", "热水", "洗衣", "电费", "充值", "其他"])
    }

    /// Rows draw one grey line symbol per kind (SF Symbols names), no emoji.
    func testEachKindHasItsLineSymbol() {
        XCTAssertEqual(CardRecordKind.allCases.map(\.symbol),
                       ["fork.knife", "shower", "washer", "bolt", "plus.circle", "bag"])
        let item = RecentItem(id: "1", kind: .laundry, title: "洗衣", date: noon, detail: nil, amount: nil, source: .app)
        XCTAssertEqual(item.symbol, "washer")
    }

    func testTheFixtureRecordsAreClassified() throws {
        let data = try Data(contentsOf: FixtureLoader.root.appendingPathComponent("ecykt/card-getRecordList-ok.json"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = (root["response"] as? [String: Any])?["body"] as? [String: Any]
        let rows = try XCTUnwrap((body?["data"] as? [String: Any])?["rows"] as? [[String: Any]])
        let kinds = rows.map { CardRecordKind.of(name: $0["transname"] as? String ?? "") }
        XCTAssertEqual(kinds, [.shower, .shower, .shower, .shower, .canteen])
    }

    // MARK: Merchant names

    func testMerchantNamesLoseTheSchoolsWords() {
        XCTAssertEqual(MerchantName.clean("POS消费(示例饭堂POS)(示例饭堂POS)01档口示例面馆"), "示例面馆")
        XCTAssertNil(MerchantName.clean("蓝牙热水(中卡)(蓝牙热水(中卡))热水POS01(中卡)"), "nothing beyond the kind")
        XCTAssertEqual(MerchantName.clean("POS消费(示例饭堂POS)"), "示例饭堂")
        XCTAssertNil(MerchantName.clean("消费"))
        XCTAssertNil(MerchantName.clean("校园卡充值"))
        XCTAssertEqual(MerchantName.clean("示例超市（一楼）"), "示例超市")
        for raw in ["POS消费(示例饭堂POS)(示例饭堂POS)01档口示例面馆", "银行圈存", "POS消费", "交易扣款"] {
            let shown = MerchantName.clean(raw) ?? ""
            for word in MerchantName.hidden { XCTAssertFalse(shown.contains(word), "\(raw) → \(shown)") }
        }
    }

    // MARK: Record times

    /// The home header's date and weekday are the school's, whatever the phone's time zone:
    /// 17:30 UTC on Wednesday 28 October is already Thursday the 29th in the school.
    func testTheHomeDateIsTheSchoolsDay() {
        let moment = Date(timeIntervalSince1970: 1_793_208_600) // 2026-10-28 17:30 UTC
        var phone = Calendar(identifier: .gregorian)
        phone.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(phone.component(.day, from: moment), 28)
        XCTAssertEqual(SchoolCalendar.dayTitle(moment), "10月29日")
        XCTAssertEqual(SchoolCalendar.weekday(moment), "周四")
    }

    func testRecordTimesAreSchoolTime() {
        XCTAssertEqual(record("20261029", "235959", "x", "1").moment(), moment(29, 23, 59).addingTimeInterval(59))
        XCTAssertEqual(record("20261030", "70500", "x", "1").moment(), moment(30, 7, 5), "a leading zero left out")
        XCTAssertNil(record("2026103", "120000", "x", "1").moment())
        XCTAssertNil(record("20260231", "120000", "x", "1").moment(), "no such day")
        XCTAssertNil(record("20261030", "250000", "x", "1").moment())
    }

    // MARK: Merge

    func testNewestFirstUpToTheLimit() {
        let card = (0..<6).map { record("20261030", String(format: "%02d0000", 6 + $0), "示例超市", "1") }
        let items = RecentFeed.items(card: card, app: [], limit: 4)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.map(\.date), [moment(30, 11), moment(30, 10), moment(30, 9), moment(30, 8)])
    }

    /// Home shows six rows under the 洗衣 block, eight when there is none.
    /// Home is given twenty rows and shows the whole ones that fit its screen.
    func testHomeGetsTwentyRowsToFitTheScreen() {
        XCTAssertEqual(RecentFeed.homeCandidates, 20)
        let card = (0..<24).map { record("20261030", String(format: "%02d0000", $0), "示例超市", "1") }
        let rows = RecentFeed.items(card: card, app: [], limit: RecentFeed.homeCandidates)
        XCTAssertEqual(rows.map(\.date), (0..<20).map { moment(30, 23 - $0) })
    }

    /// A full page of records (the school's long names) is saved whole in the snapshot the
    /// widget shares, and after the app's own shower and laundry order take the place of their
    /// card records, home's twenty rows are still there.
    func testTwentyRowsSurviveTheSavedSnapshotAndTheMerge() throws {
        let canteen = "POS消费(示例饭堂POS)(示例饭堂POS)01档口示例面馆"
        var records = (0..<CardActivity.pageSize - 2).map { i in
            record(i < 24 ? "20261030" : "20261029", String(format: "%02d%02d00", 11 - (i % 24) / 3, 50 - (i % 3) * 10), canteen, "9")
        }
        records.insert(record("20261030", "115500", "蓝牙热水(中卡)(蓝牙热水(中卡))热水POS01(中卡)", "1.32"), at: 0)
        records.insert(record("20261030", "115200", "示例洗衣机", "4"), at: 1)
        let store = SharedSnapshotStore(store: InMemorySecureStore())
        try store.saveSnapshot(HomeSnapshot(activity: activity(records, fetchedAt: noon), checkedAt: noon))
        let saved = try XCTUnwrap(try store.loadSnapshot()?.activity.value?.records)
        XCTAssertEqual(saved.count, CardActivity.pageSize)

        let shower = AppActivity(id: "s1", kind: .shower(minutes: 11), date: moment(30, 11, 54), amount: Money(fen: 132))
        let laundry = AppActivity(id: "l1", kind: .laundry(program: "标准洗"), date: moment(30, 11, 51),
                                  amount: Money(fen: 400), detail: "3 号机")
        let withLaundry = RecentFeed.items(card: saved, app: [shower, laundry], limit: RecentFeed.homeCandidates)
        XCTAssertEqual(withLaundry.count, 20)
        XCTAssertEqual(withLaundry.prefix(2).map(\.title), ["热水 · 11 分钟", "洗衣 · 标准洗"])
        XCTAssertEqual(withLaundry.filter { $0.kind == .shower || $0.kind == .laundry }.count, 2, "each once")

        let withoutLaundry = RecentFeed.items(card: saved, app: [shower], limit: RecentFeed.homeCandidates)
        XCTAssertEqual(withoutLaundry.count, 20)
        XCTAssertEqual(withoutLaundry.filter { $0.kind == .shower }.map(\.source), [.app])
    }

    /// The card's hot-water record and the app's shower within the window, same amount: one row,
    /// the app's (it knows the minutes).
    func testTheSameShowerAppearsOnceAsTheAppsRecord() {
        let card = [record("20261030", "080500", "蓝牙热水(中卡)热水POS01", "1.32"),
                    record("20261030", "074000", "POS消费(示例饭堂POS)01档口示例面馆", "5.4")]
        let shower = AppActivity(id: "s1", kind: .shower(minutes: 11), date: moment(30, 8, 2), amount: Money(fen: 132))
        let items = RecentFeed.items(card: card, app: [shower], limit: 10)
        XCTAssertEqual(items.map(\.title), ["热水 · 11 分钟", "食堂"])
        XCTAssertEqual(items.first?.source, .app)
        XCTAssertEqual(items.last?.detail, "示例面馆")
    }

    func testOnlyACloseRecordOfTheSameKindAndAmountIsTheSameEvent() {
        let shower = AppActivity(id: "s1", kind: .shower(minutes: 9), date: moment(30, 8), amount: Money(fen: 100))
        let far = record("20261030", "090100", "蓝牙热水", "1")
        let otherAmount = record("20261030", "080100", "蓝牙热水", "2")
        let otherKind = record("20261030", "080100", "示例洗衣机", "1")
        for card in [[far], [otherAmount], [otherKind]] {
            XCTAssertEqual(RecentFeed.items(card: card, app: [shower], limit: 10).count, 2, card[0].title)
        }
        let inside = record("20261030", "082900", "蓝牙热水", "1")
        XCTAssertEqual(RecentFeed.items(card: [inside], app: [shower], limit: 10).count, 1)
    }

    /// An app record without an amount takes the card's.
    func testAnAppRecordWithoutAnAmountTakesTheCards() {
        let order = AppActivity(id: "l1", kind: .laundry(program: "标准洗"), date: moment(30, 9), amount: nil, detail: "3 号机")
        let items = RecentFeed.items(card: [record("20261030", "090200", "示例洗衣机", "4")], app: [order], limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "洗衣 · 标准洗")
        XCTAssertEqual(items[0].amount, Money(fen: 400))
        XCTAssertEqual(items[0].amountText, "−¥4.00")
    }

    /// Records that can't be read: the app's own records only.
    func testUnreadableRecordsLeaveTheAppsRecords() {
        let shower = AppActivity(id: "s1", kind: .shower(minutes: nil), date: moment(30, 8), amount: nil)
        XCTAssertEqual(RecentFeed.items(card: nil, app: [shower], limit: 10).map(\.title), ["热水"])
    }

    func testAmountsReadAndSpoken() {
        let topUp = RecentItem(id: "a", kind: .topUp, title: "充值", date: noon, detail: nil, amount: Money(fen: 5000), source: .card)
        let canteen = RecentItem(id: "b", kind: .canteen, title: "食堂", date: noon, detail: nil, amount: Money(fen: 1250), source: .card)
        XCTAssertEqual(topUp.amountText, "+¥50.00")
        XCTAssertEqual(topUp.spokenAmount, "充了 50 元")
        XCTAssertEqual(canteen.amountText, "−¥12.50")
        XCTAssertEqual(canteen.spokenAmount, "花了 12.5 元")
    }

    // MARK: 昨天花了

    func activity(_ records: [CardRecord], fetchedAt: Date, complete: Bool = true,
                  begin: String = "20261028", end: String = "20261030") -> Tile<CardActivity> {
        Tile(value: CardActivity(records: records, begin: begin, end: end, complete: complete), fetchedAt: fetchedAt)
    }

    /// Yesterday in Shanghai, from 00:00:00 to 23:59:59; top-ups don't count.
    func testYesterdayIsTheSchoolsDayAndCountsMoneyOutOnly() {
        let records = [record("20261029", "000000", "示例超市", "1"),
                       record("20261029", "235959", "POS消费(示例饭堂POS)", "2.5"),
                       record("20261029", "120000", "校园卡充值", "50", flag: nil),
                       record("20261030", "000000", "示例超市", "7"),
                       record("20261028", "235959", "示例超市", "9")]
        XCTAssertEqual(CardSpending.yesterday(activity(records, fetchedAt: noon), now: noon), Money(fen: 350))
        // 00:30 in Shanghai is still the previous evening in UTC: the school's day counts.
        let earlyMorning = moment(30, 0, 30)
        XCTAssertEqual(CardSpending.yesterday(activity(records, fetchedAt: earlyMorning), now: earlyMorning), Money(fen: 350))
    }

    func testNoSpendingYesterdayIsZero() {
        let records = [record("20261030", "080000", "示例超市", "1"), record("20261029", "080000", "校园卡充值", "50", flag: nil)]
        XCTAssertEqual(CardSpending.yesterday(activity(records, fetchedAt: noon), now: noon), .zero)
    }

    /// Nothing is said when the records can't tell.
    func testUnknownYesterdayIsHidden() {
        let records = [record("20261029", "080000", "示例超市", "1")]
        XCTAssertNil(CardSpending.yesterday(nil, now: noon), "never read")
        XCTAssertNil(CardSpending.yesterday(Tile<CardActivity>(error: .offline, errorAt: noon), now: noon), "unreadable")
        XCTAssertNil(CardSpending.yesterday(activity(records, fetchedAt: noon, complete: false), now: noon), "page cut short")
        XCTAssertNil(CardSpending.yesterday(activity(records, fetchedAt: moment(29, 22)), now: noon), "read before today")
        XCTAssertNil(CardSpending.yesterday(activity(records, fetchedAt: noon, begin: "20261030"), now: noon), "range without it")
        let unreadable = records + [record("20261029", "xx", "示例超市", "1")]
        XCTAssertNil(CardSpending.yesterday(activity(unreadable, fetchedAt: noon), now: noon), "a time that can't be read")
    }

    /// A refund, a reversal or a grant is money in: a 12 元 meal refunded the same day is
    /// 「昨天花了 ¥12.00」, not 24; a 100 元 grant is not spending.
    func testRefundsAndGrantsAreMoneyIn() {
        let records = [record("20261029", "120000", "POS消费(示例饭堂POS)01档口示例面馆", "12"),
                       record("20261029", "121000", "POS消费退款", "12", flag: nil),
                       record("20261029", "080000", "伙食补贴", "100", flag: nil),
                       record("20261029", "090000", "消费冲正", "3", flag: nil),
                       record("20261029", "091000", "撤销交易", "2", flag: nil)]
        XCTAssertEqual(CardSpending.yesterday(activity(records, fetchedAt: noon), now: noon), Money(fen: 1200))
        let items = RecentFeed.items(card: records, app: [], limit: 10)
        XCTAssertEqual(items.first { $0.date == moment(29, 12, 10) }?.amountText, "+¥12.00")
        XCTAssertEqual(items.first { $0.date == moment(29, 12, 10) }?.spokenAmount, "进账 12 元")
        XCTAssertEqual(items.first { $0.date == moment(29, 8) }?.amountText, "+¥100.00")
        XCTAssertEqual(items.first { $0.date == moment(29, 12) }?.amountText, "−¥12.00")
    }

    /// Paying electricity or hot water from the card can carry 充值 / 转入 in its name; with
    /// flag 「1」 it is money out, and its kind is what was paid for.
    func testPaymentsNamedLikeTopUpsAreMoneyOut() {
        let records = [record("20261029", "100000", "电费充值(99栋)", "20"),
                       record("20261029", "110000", "转入水控", "10"),
                       record("20261029", "120000", "校园卡充值", "50", flag: nil),
                       record("20261029", "130000", "银行圈存", "30", flag: "2")]
        XCTAssertEqual(records.map(\.kind), [.electricity, .shower, .topUp, .topUp])
        XCTAssertEqual(CardSpending.yesterday(activity(records, fetchedAt: noon), now: noon), Money(fen: 3000))
        let items = RecentFeed.items(card: records, app: [], limit: 10)
        XCTAssertEqual(items.first { $0.date == moment(29, 10) }?.amountText, "−¥20.00")
        XCTAssertEqual(items.first { $0.date == moment(29, 11) }?.amountText, "−¥10.00")
        XCTAssertEqual(items.first { $0.date == moment(29, 12) }?.amountText, "+¥50.00")
        XCTAssertEqual(items.first { $0.date == moment(29, 13) }?.amountText, "+¥30.00")
    }

    /// A refund flagged as a payment is still taken as one: only the flag says which way.
    func testFlagOneIsMoneyOutWhateverTheName() {
        let refund = record("20261029", "121000", "POS消费退款", "12")
        XCTAssertEqual(refund.flow, .moneyOut)
        XCTAssertEqual(record("20261029", "121000", "POS消费退款", "12", flag: nil).flow, .moneyIn)
        XCTAssertEqual(record("20261029", "121000", "示例超市", "12", flag: "2").flow, .unknown)
    }

    /// A record that may be money in or out (a negative amount, an unseen direction flag)
    /// hides yesterday's total and shows its amount without a sign.
    func testARecordOfUnknownDirectionHidesTheTotal() {
        let negative = [record("20261029", "120000", "示例超市", "12"), record("20261029", "130000", "示例超市", "-12")]
        XCTAssertNil(CardSpending.yesterday(activity(negative, fetchedAt: noon), now: noon), "negative amount")
        var flagged = record("20261029", "130000", "示例超市", "5")
        flagged.direction = "2"
        XCTAssertNil(CardSpending.yesterday(activity([flagged], fetchedAt: noon), now: noon), "another flag")
        var noFlag = record("20261029", "130000", "示例超市", "5")
        noFlag.direction = nil
        XCTAssertEqual(CardSpending.yesterday(activity([noFlag], fetchedAt: noon), now: noon), Money(fen: 500))
        let items = RecentFeed.items(card: negative, app: [], limit: 10)
        XCTAssertEqual(items.first { $0.date == moment(29, 13) }?.amountText, "¥12.00")
        XCTAssertEqual(items.first { $0.date == moment(29, 13) }?.spokenAmount, "12 元")
        // Unknown records of other days don't matter.
        let otherDay = [record("20261029", "120000", "示例超市", "12"), record("20261030", "090000", "示例超市", "-3")]
        XCTAssertEqual(CardSpending.yesterday(activity(otherDay, fetchedAt: noon), now: noon), Money(fen: 1200))
    }

    func testTheRangeIsThreeSchoolDays() {
        let r = CardActivity.range(at: moment(30, 0, 10))
        XCTAssertEqual(r.begin, "20261028")
        XCTAssertEqual(r.end, "20261030")
    }
}
