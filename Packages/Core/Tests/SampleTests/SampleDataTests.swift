import XCTest
import Core

/// The synthetic data the DEBUG demos and the sample mode share: the same values as the demos
/// had, never later than now, and the full 校园卡记录 sample pages like the school's.
final class SampleDataTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testHomeSnapshotHasTheDemoNumbers() {
        let s = SampleData.homeSnapshot(now: now)
        XCTAssertEqual(s.card.value, Money(yuanString: "86.50"))
        XCTAssertEqual(s.power.value?.remainingKWh, Decimal(string: "42.6"))
        XCTAssertEqual(s.power.value?.dailyUseKWh, Decimal(string: "4.6"))
        XCTAssertEqual(s.roomLabel, "3栋108")
        XCTAssertFalse(s.activity.value?.records.isEmpty ?? true)
    }

    func testNoRecordIsLaterThanAQuarterHourAgo() {
        let school = SchoolCalendar.shanghai
        let home = SampleData.homeSnapshot(now: now).activity.value?.records ?? []
        let all = SampleData.cardRecords(days: SampleData.recordDays, now: now)
        for record in home + all {
            XCTAssertLessThanOrEqual(record.moment(calendar: school) ?? .distantFuture, now.addingTimeInterval(-15 * 60))
        }
    }

    func testRecordsAreNewestFirstWithVouchers() {
        let school = SchoolCalendar.shanghai
        let rows = SampleData.cardRecords(days: SampleData.recordDays, now: now)
        XCTAssertGreaterThan(rows.count, 60)
        XCTAssertTrue(rows.allSatisfy { $0.voucher?.hasPrefix("99") == true })
        let moments = rows.compactMap { $0.moment(calendar: school) }
        XCTAssertEqual(moments, moments.sorted(by: >))
    }

    func testRecordPagesSplitTheRange() {
        let rows = SampleData.cardRecords(days: SampleData.recordDays, now: now)
        let begin = rows.map(\.date).min()!, end = rows.map(\.date).max()!
        let first = SampleData.recordPage(rows, CardHistoryQuery(begin: begin, end: end, page: 1, pageSize: 20))
        let past = SampleData.recordPage(rows, CardHistoryQuery(begin: begin, end: end, page: 99, pageSize: 20))
        XCTAssertEqual(first.total, rows.count)
        XCTAssertEqual(first.rows.count, 20)
        XCTAssertTrue(past.rows.isEmpty)
    }

    func testAppActivitiesAreTheLastShowerAndLaundryOrder() {
        let items = SampleData.appActivities(now: now)
        XCTAssertEqual(items.map(\.id), ["demo-shower", "demo-laundry"])
        XCTAssertEqual(items.first?.amount, SampleData.lastShowerCost)
    }

    func testWasherIsFreeWithFourPrograms() {
        let washer = SampleData.washerSnapshot(status: 0)
        XCTAssertEqual(washer.info.deviceNo, "3")
        XCTAssertEqual(washer.info.programs.count, 4)
        XCTAssertTrue(washer.scan.createOrderEnabled)
        XCTAssertFalse(SampleData.washerSnapshot(status: 1).scan.createOrderEnabled)
    }

    func testShowerRecordsByName() {
        XCTAssertEqual(SampleData.showerRecord("sh-done", now: now)?.phase, .done)
        XCTAssertEqual(SampleData.showerRecord("sh-run", now: now)?.phase, .running)
        XCTAssertNil(SampleData.showerRecord("nothing", now: now))
    }
}
