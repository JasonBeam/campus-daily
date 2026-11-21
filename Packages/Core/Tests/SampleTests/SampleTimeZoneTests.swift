//
//  SampleTimeZoneTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
import Core

/// The sample on a phone in any time zone: its card records, its own shower and laundry order and
/// the shower page all read on the phone's clock, the same shower shows once, and nothing is
/// later than now.
final class SampleTimeZoneTests: XCTestCase {
    private var savedZone: TimeZone!
    /// Every three hours of a day, so the phone's day and the school's differ for some of them.
    private let nows = (0..<8).map { Date(timeIntervalSince1970: 1_790_000_000 + Double($0) * 3 * 3600) }
    private let zones = ["America/Los_Angeles", "Asia/Shanghai", "Europe/London", "Pacific/Auckland"]

    override func setUp() {
        savedZone = NSTimeZone.default
    }

    override func tearDown() {
        NSTimeZone.default = savedZone
    }

    /// The phone's own calendar, as the shower page and the status bar read the time.
    private func phone() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    func testRecordsReadOnThePhonesClockAndNeverLaterThanNow() throws {
        for zone in zones {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: zone))
            let calendar = phone()
            for now in nows {
                let home = SampleData.homeSnapshot(now: now).activity.value?.records ?? []
                let all = SampleData.cardRecords(days: SampleData.recordDays, now: now)
                XCTAssertFalse(home.isEmpty)
                for record in home + all {
                    let moment = try XCTUnwrap(record.moment(calendar: calendar))
                    XCTAssertLessThanOrEqual(moment, now.addingTimeInterval(-15 * 60), "\(zone) \(record.date) \(record.time)")
                }
                // Meals at meal times on the phone's clock.
                let clocks = Set(home.filter { $0.kind == .canteen && !$0.paidWithWeChat }.map { String($0.time.prefix(4)) })
                XCTAssertTrue(clocks.isSubset(of: ["0742", "1216", "1758"]), "\(zone) \(clocks)")
            }
        }
    }

    func testTheShowerShowsOnceAtTheTimeTheShowerPageSays() throws {
        for zone in zones {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: zone))
            let calendar = phone()
            for now in nows {
                let card = SampleData.homeSnapshot(now: now).activity.value?.records
                let app = SampleData.appActivities(now: now)
                let items = RecentFeed.items(card: card, app: app, limit: .max, calendar: calendar)
                let showers = items.filter { $0.kind == .shower }
                XCTAssertEqual(showers.count, 1, "\(zone): the card's record of the sample shower is the app's shower")
                let ended = now.addingTimeInterval(-SampleData.showerAgo)
                XCTAssertEqual(showers.first.map { CardDays.clock($0.date, calendar: calendar) },
                               CardDays.clock(ended, calendar: calendar), zone)
                XCTAssertEqual(items.filter { $0.kind == .laundry }.count, 1, zone)
            }
        }
    }
}
