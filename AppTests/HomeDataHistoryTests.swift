//
//  HomeDataHistoryTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
import Core
@testable import XiaoRiChang

/// Finished laundry orders on home's 最近 and in 校园卡记录 / 订单: 「· 支付宝」 under the title,
/// the amount only for a 50 that has one, the word for 51/52/53 in each theme's own words, a
/// read-only row, and none while 学校洗衣机 is off.
final class HomeDataHistoryTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_793_332_800)

    func entry(_ status: String, amount: Money? = nil, key: String = "k1") -> LaundryHistoryEntry {
        LaundryHistoryEntry(key: key, owner: "o", at: at, program: "标准洗", machine: "3", status: status, amount: amount)
    }

    func testRowsFromHistory() throws {
        let rows = HomeData.historyActivities([entry("50", amount: Money(fen: 400), key: "a"), entry("50", key: "b"),
                                               entry("51", key: "c"), entry("52", key: "d"), entry("53", key: "e")])
        XCTAssertEqual(rows.map(\.id), ["laundry-h-a", "laundry-h-b", "laundry-h-c", "laundry-h-d", "laundry-h-e"])
        XCTAssertTrue(rows.allSatisfy { $0.detail == "3 号机 · 支付宝" })
        XCTAssertTrue(rows.allSatisfy { !$0.opensPage && !$0.matchesCard })
        XCTAssertEqual(rows.map(\.amount), [Money(fen: 400), nil, nil, nil, nil])
        XCTAssertEqual(rows.map(\.outcome), [nil, nil, .unpaid, .notStarted, .cancelled])
        XCTAssertEqual(rows[0].kind, .laundry(program: "标准洗"))
        XCTAssertEqual(rows[0].date, at)
    }

    func testHiddenWhenSchoolLaundryIsOff() {
        var data = HomeData()
        data.appActivities = HomeData.historyActivities([entry("53")])
        XCTAssertEqual(data.recentActivities.count, 1)
        data.laundryEnabled = false
        XCTAssertEqual(data.recentActivities.count, 0)
    }

    func testRowsAreReadOnlyAndSpeakTheirWord() {
        let items = RecentFeed.items(card: nil, app: HomeData.historyActivities([entry("52")]), limit: 5)
        let item = items[0]
        XCTAssertFalse(item.opensPage)
        let warm = RecentRow(item: item).spokenLabel
        XCTAssertTrue(warm.hasPrefix("洗衣 · 标准洗，"), warm)
        XCTAssertTrue(warm.hasSuffix("3 号机 · 支付宝，没启动"), warm)
        let clear = ClearRecordRow(item: item).spokenLabel
        XCTAssertTrue(clear.hasSuffix("3 号机 · 支付宝，未启动"), clear)

        let paid = RecentFeed.items(card: nil, app: HomeData.historyActivities([entry("50", amount: Money(fen: 400))]), limit: 5)[0]
        XCTAssertTrue(RecentRow(item: paid).spokenLabel.hasSuffix("支付宝，花了 4 元"))
        XCTAssertTrue(ClearRecordRow(item: paid).spokenLabel.hasSuffix("支付宝，花了 4 元"))
        let bare = RecentFeed.items(card: nil, app: HomeData.historyActivities([entry("50")]), limit: 5)[0]
        XCTAssertTrue(RecentRow(item: bare).spokenLabel.hasSuffix("3 号机 · 支付宝"))
    }
}
