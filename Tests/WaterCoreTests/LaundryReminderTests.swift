import XCTest
@testable import WaterCore

final class LaundryReminderTests: XCTestCase {
    func testRunningOrderAndReminderShareDeadlineAcrossRefreshAndCompletion() throws {
        var record = LaundryCheckoutRecord(deviceId:"machine",programId:1,programName:"wash",expectedPrice:2,createdAt:Date(timeIntervalSince1970:900),stage:.created)
        func update(_ status:String,_ remaining:Int,_ timestamp:TimeInterval) throws -> LaundryReminderAction {
            let json = "{\"orderId\":\"one\",\"deviceId\":\"machine\",\"status\":\"\(status)\",\"remainTime\":\(remaining)}"
            let order = try JSONDecoder().decode(LaundryOrder.self,from:Data(json.utf8))
            record.observeOrder(order,at:Date(timeIntervalSince1970:timestamp))
            return LaundryReminderPolicy.action(status:status,remaining:remaining,observedAt:timestamp,now:timestamp,tracked:true,alreadyReminded:false,deadline:record.countdownDeadline?.timeIntervalSince1970)
        }
        XCTAssertEqual(try update("40",120,1000),.estimate(1120))
        XCTAssertEqual(try update("40",120,1030),.estimate(1120))
        XCTAssertEqual(try update("40",60,1060),.estimate(1120))
        XCTAssertEqual(try update("50",60,1090),.ignore)
        XCTAssertEqual(record.countdownDeadline,Date(timeIntervalSince1970:1120))
    }
    func testDeliveredReminderIsRecordedOnceAndBounded() {
        let first = LaundryReminderPolicy.recordDelivered("one",in:[])
        XCTAssertEqual(LaundryReminderPolicy.recordDelivered("one",in:first),["one"])
        let full = (0..<64).map(String.init)
        let updated = LaundryReminderPolicy.recordDelivered("new",in:full)
        XCTAssertEqual(updated.count,64)
        XCTAssertFalse(updated.contains("0"))
        XCTAssertEqual(updated.last,"new")
        let firstDelivery = LaundryReminderPolicy.recordDeliveryTime(1000,for:"one",keys:[],dates:[:])
        let duplicate = LaundryReminderPolicy.recordDeliveryTime(1100,for:"one",keys:firstDelivery.keys,dates:firstDelivery.dates)
        XCTAssertEqual(duplicate.dates["one"],1000)
        let oldDates = Dictionary(uniqueKeysWithValues:full.map { ($0, 1.0) })
        let trimmed = LaundryReminderPolicy.recordDeliveryTime(1200,for:"new",keys:full,dates:oldDates)
        XCTAssertEqual(trimmed.dates.count,64)
        XCTAssertNil(trimmed.dates["0"])
        XCTAssertEqual(trimmed.dates["new"],1200)
        let suite = "LaundryReminderTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(trimmed.dates,forKey:"dates")
        let restored = (defaults.dictionary(forKey:"dates") ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        XCTAssertEqual(restored["new"],1200)
    }
    func testRepeatedServerRemainingDoesNotRestartCountdown() throws {
        var record = LaundryCheckoutRecord(deviceId:"machine",programId:1,programName:"普通洗",expectedPrice:2,createdAt:Date(timeIntervalSince1970:900),stage:.created)
        func order(_ remaining:Int, status:String = "40") throws -> LaundryOrder {
            let json = "{\"orderId\":\"one\",\"deviceId\":\"machine\",\"status\":\"\(status)\",\"remainTime\":\(remaining)}"
            return try JSONDecoder().decode(LaundryOrder.self,from:Data(json.utf8))
        }
        record.observeOrder(try order(60),at:Date(timeIntervalSince1970:1000))
        XCTAssertEqual(record.countdownDeadline,Date(timeIntervalSince1970:1060))
        record.observeOrder(try order(60),at:Date(timeIntervalSince1970:1030))
        XCTAssertEqual(record.countdownDeadline,Date(timeIntervalSince1970:1060))
        XCTAssertEqual(record.orderUpdatedAt,Date(timeIntervalSince1970:1030))
        let restored = try JSONDecoder().decode(LaundryCheckoutRecord.self,from:JSONEncoder().encode(record))
        XCTAssertEqual(restored.countdownDeadline,Date(timeIntervalSince1970:1060))
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as? [String:Any])
        legacyJSON.removeValue(forKey:"countdownDeadline")
        legacyJSON.removeValue(forKey:"countdownSamples")
        var legacy = try JSONDecoder().decode(LaundryCheckoutRecord.self,from:JSONSerialization.data(withJSONObject:legacyJSON))
        legacy.observeOrder(try order(60),at:Date(timeIntervalSince1970:1040))
        XCTAssertEqual(legacy.countdownDeadline,Date(timeIntervalSince1970:1090))
        record.observeOrder(try order(120),at:Date(timeIntervalSince1970:1040))
        XCTAssertEqual(record.countdownDeadline,Date(timeIntervalSince1970:1160))
        record.observeOrder(try order(60,status:"50"),at:Date(timeIntervalSince1970:1050))
        XCTAssertEqual(record.countdownDeadline,Date(timeIntervalSince1970:1160))
        XCTAssertEqual(record.countdownSamples?.last?.status,"50")
        for i in 0..<140 { record.observeOrder(try order(60),at:Date(timeIntervalSince1970:2000+Double(i))) }
        XCTAssertEqual(record.countdownSamples?.count,128)
        XCTAssertEqual(record.countdownSamples?.last?.remaining,60)
    }
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
    func testCompletionDoesNotReplaceOrResetCountdown() {
        XCTAssertEqual(decide("40",seconds:30),.estimate(1030))
        XCTAssertEqual(decide("50",seconds:0),.ignore)
        XCTAssertEqual(decide("50",seconds:60),.ignore)
        XCTAssertEqual(decide("50",seconds:0,reminded:true),.ignore)
    }
    func testCompletionWithoutRunningCountdownDoesNotInventOne() {
        XCTAssertEqual(decide("50",seconds:60,tracked:false),.ignore)
        XCTAssertEqual(decide("50",tracked:false,reminded:true),.ignore)
        XCTAssertEqual(decide("50",observed:900,tracked:false),.ignore)
    }
    func testMissingPendingRequestDoesNotProveDelivery() {
        // The caller must use actual delivered notifications or its successful completion marker.
        XCTAssertEqual(decide("40",seconds:90,tracked:true,reminded:false),.estimate(1090))
        XCTAssertEqual(decide("50",seconds:0,tracked:true,reminded:false),.ignore)
        XCTAssertEqual(decide("50",seconds:60,tracked:true,reminded:false),.ignore)
    }
    private func decide(_ status:String,seconds:Int=300,observed:Double=1000,tracked:Bool=true,reminded:Bool=false)->LaundryReminderAction {
        LaundryReminderPolicy.action(status:status,remaining:seconds,observedAt:observed,now:1010,tracked:tracked,alreadyReminded:reminded)
    }
}
