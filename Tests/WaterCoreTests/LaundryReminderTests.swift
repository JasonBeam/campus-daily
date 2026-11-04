import XCTest
@testable import WaterCore

final class LaundryReminderTests: XCTestCase {
    func testFailuresAndCancellationNeverAnnounceCompletion() {
        for status in ["51","52","53"] {
            XCTAssertEqual(decide(status),.clear)
        }
        XCTAssertEqual(decide("50"),.ignore)
    }
    func testHistoricalAndPreviouslyRemindedOrdersStayQuiet() {
        XCTAssertEqual(decide("50",tracked:false),.ignore)
        XCTAssertEqual(decide("50",reminded:true),.ignore)
        XCTAssertEqual(decide("40",reminded:true),.ignore)
    }
    func testEstimateUsesObservationTimeAndRejectsStaleOrInvalidData() {
        XCTAssertEqual(decide("40"),.estimate(1300))
        XCTAssertEqual(decide("20"),.ignore) // Paid is not running.
        XCTAssertEqual(decide("unknown"),.ignore)
        XCTAssertEqual(decide("40",seconds:0),.estimate(1000))
        XCTAssertEqual(decide("21",seconds:0),.ignore)
        XCTAssertEqual(decide("40",seconds:86401),.ignore)
        XCTAssertEqual(decide("40",observed:900),.ignore)
        XCTAssertEqual(decide("40",observed:1200),.ignore)
    }
    func testConfirmedCompletionCanReplaceForecastWithCompletionNotice() {
        XCTAssertEqual(decide("40",seconds:30),.estimate(1030))
        XCTAssertEqual(decide("50",seconds:0,recent:true),.completed)
        XCTAssertEqual(decide("50",seconds:0,reminded:true,recent:true),.ignore)
    }
    func testRecentCompletionWithoutEverSeeingRunningCountdownStillNotifies() {
        // User starts in Alipay, then returns only after the server already reports complete.
        XCTAssertEqual(decide("50",seconds:60,tracked:false,recent:true),.completed)
        XCTAssertEqual(decide("50",tracked:false,reminded:true,recent:true),.ignore)
        XCTAssertEqual(decide("50",tracked:false,recent:false),.ignore)
        XCTAssertEqual(decide("50",observed:900,tracked:false,recent:true),.ignore)
    }
    func testMissingPendingRequestDoesNotProveDelivery() {
        // The caller must use actual delivered notifications or its successful completion marker.
        XCTAssertEqual(decide("40",seconds:90,tracked:true,reminded:false),.estimate(1090))
        XCTAssertEqual(decide("50",tracked:true,reminded:false,recent:true),.completed)
    }
    private func decide(_ status:String,seconds:Int=300,observed:Double=1000,tracked:Bool=true,reminded:Bool=false,recent:Bool=false)->LaundryReminderAction {
        LaundryReminderPolicy.action(status:status,remaining:seconds,observedAt:observed,now:1010,tracked:tracked,alreadyReminded:reminded,recentOrder:recent)
    }
}
