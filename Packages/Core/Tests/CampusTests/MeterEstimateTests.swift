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
}
