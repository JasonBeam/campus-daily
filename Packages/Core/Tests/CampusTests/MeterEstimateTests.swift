import XCTest
@testable import Core

/// `preUseDay` is the school's estimate of how many days the remaining electricity lasts (feedback
/// 988405a3: 13.6 度 and, 48 minutes and a top-up later, 182.5 度 both gave 「够用约 11 天」).
final class MeterEstimateTests: XCTestCase {
    func meter(kwh: Decimal?, days: Decimal?) -> Meter {
        Meter(comAddress: "M1", name: "3栋108", remainingKWh: kwh, estimatedDaysLeft: days)
    }

    /// Only an estimate above 0 and at most a year is used.
    func testOnlyAPlausibleEstimateIsUsable() {
        for days: Decimal? in [nil, 0, -1, 365.5, 1000] {
            XCTAssertNil(meter(kwh: 42.6, days: days).usableDaysLeft, "\(String(describing: days))")
        }
        XCTAssertEqual(meter(kwh: 42.6, days: 365).usableDaysLeft, 365)
        XCTAssertEqual(meter(kwh: 13.6, days: 1.2).usableDaysLeft, 1.2)
    }

    /// 9: the daily average behind the estimate is remaining ÷ days.
    func testDailyAverageIsRemainingOverTheDays() {
        XCTAssertEqual(meter(kwh: 52, days: 3.2).averageDailyKWh, 16.25)
        XCTAssertEqual(meter(kwh: 13.6, days: 1.2).averageDailyKWh.map(round1), 11.3)
        XCTAssertEqual(meter(kwh: 182.5, days: 16.1).averageDailyKWh.map(round1), 11.3)
    }

    /// 9: no average from an estimate that can't be used, or without anything left.
    func testNoDailyAverageWithoutAUsableEstimate() {
        for days: Decimal? in [nil, 0, -1, 365.5, 1000] {
            XCTAssertNil(meter(kwh: 42.6, days: days).averageDailyKWh, "\(String(describing: days))")
        }
        XCTAssertNil(meter(kwh: nil, days: 3).averageDailyKWh)
        XCTAssertNil(meter(kwh: 0, days: 3).averageDailyKWh)
        XCTAssertNil(meter(kwh: -2, days: 3).averageDailyKWh)
    }

    /// 12: a meter saved by an older build (its `preUseDay` under `dailyUseKWh`) still decodes,
    /// and means the same days.
    func testOldCacheDecodesAsDays() throws {
        let old = #"{"comAddress":"M1","name":"3栋108","remainingKWh":13.6,"dailyUseKWh":1.2}"#
        let decoded = try JSONDecoder().decode(Meter.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.estimatedDaysLeft, 1.2)
        XCTAssertEqual(decoded.remainingKWh, 13.6)
        let again = try JSONDecoder().decode(Meter.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again, decoded)
        let keys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        XCTAssertNotNil(keys?["dailyUseKWh"], "an older build reading this cache finds the same key")
    }

    private func round1(_ value: Decimal) -> Decimal {
        var value = value, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 1, .plain)
        return rounded
    }
}
