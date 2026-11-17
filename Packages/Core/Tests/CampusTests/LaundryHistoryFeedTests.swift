import XCTest
@testable import Core
import CoreTestSupport

/// Finished laundry orders paid with Alipay in 最近 and 校园卡记录: their own rows, read-only,
/// never matched to a card record and never in a day's 「花了」.
final class LaundryHistoryFeedTests: XCTestCase {
    let cal = SchoolCalendar.shanghai
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))! }

    func card(_ time: String, _ title: String, _ yuan: String) -> CardRecord {
        CardRecord(date: "20261030", time: time, title: title, amount: Money(yuanString: yuan)!, balanceAfter: nil,
                   direction: "1", voucher: "99" + time)
    }

    func alipay(_ status: AppActivity.Outcome? = nil, amount: Money? = Money(fen: 400), at: Date) -> AppActivity {
        AppActivity(id: "laundry-h-k1", kind: .laundry(program: "标准洗"), date: at, amount: amount,
                    detail: "3 号机 · 支付宝", outcome: status, opensPage: false, matchesCard: false)
    }

    func testAlipayHistoryDoesNotConsumeCardRecord() {
        let washer = card("115000", "示例洗衣机", "4.00")
        let items = RecentFeed.items(card: [washer], app: [alipay(at: noon.addingTimeInterval(-300))], limit: 10, calendar: cal)
        XCTAssertEqual(items.count, 2, "the card's own laundry row stays")
        XCTAssertEqual(items.filter { $0.source == .card }.count, 1)
        let app = items.first { $0.source == .app }
        XCTAssertEqual(app?.opensPage, false)
        XCTAssertEqual(app?.amount, Money(fen: 400))
        // No amount of its own: none borrowed from the card.
        let bare = RecentFeed.items(card: [washer], app: [alipay(amount: nil, at: noon.addingTimeInterval(-300))], limit: 10, calendar: cal)
        XCTAssertNil(bare.first { $0.source == .app }?.amount)
        XCTAssertEqual(bare.count, 2)
    }

    func testOutcomeWords() {
        let item = RecentFeed.items(card: nil, app: [alipay(.notStarted, amount: nil, at: noon)], limit: 10, calendar: cal)[0]
        XCTAssertEqual(item.outcome, .notStarted)
        XCTAssertEqual(AppActivity.Outcome.unpaid.word(clear: false), "没付款")
        XCTAssertEqual(AppActivity.Outcome.notStarted.word(clear: false), "没启动")
        XCTAssertEqual(AppActivity.Outcome.cancelled.word(clear: false), "已取消")
        XCTAssertEqual(AppActivity.Outcome.unpaid.word(clear: true), "未付款")
        XCTAssertEqual(AppActivity.Outcome.notStarted.word(clear: true), "未启动")
        XCTAssertEqual(AppActivity.Outcome.cancelled.word(clear: true), "已取消")
    }

    /// Existing app rows still open their page and still stand for the card row.
    func testOrdinaryAppRowsUnchanged() {
        let washer = card("115000", "示例洗衣机", "4.00")
        let open = AppActivity(id: "laundry-1", kind: .laundry(program: "标准洗"), date: noon.addingTimeInterval(-300), amount: nil)
        let items = RecentFeed.items(card: [washer], app: [open], limit: 10, calendar: cal)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].opensPage, true)
        XCTAssertEqual(items[0].amount, Money(fen: 400))
        XCTAssertNil(items[0].outcome)
    }

    func testHistoryNotInDayTotal() {
        var history = CardHistory(now: noon, calendar: cal)
        let query = history.nextQuery!
        history.receive(CardRecordPage(total: 1, rows: [card("110000", "POS消费示例面馆", "12.00")]), for: query)
        let days = CardDays.groups(history: history, app: [alipay(amount: Money(fen: 400), at: noon.addingTimeInterval(-600))],
                                   now: noon, calendar: cal)
        XCTAssertEqual(days.first?.items.count, 2)
        XCTAssertEqual(days.first?.total, Money(fen: 1200), "the Alipay order is not card money")
    }

    func testOfflineShowsHistory() {
        let days = CardDays.groups(history: nil, app: [alipay(.cancelled, amount: nil, at: noon)], now: noon, calendar: cal)
        XCTAssertEqual(days.first?.items.map(\.outcome), [.cancelled])
        XCTAssertNil(days.first?.total)
    }
}
