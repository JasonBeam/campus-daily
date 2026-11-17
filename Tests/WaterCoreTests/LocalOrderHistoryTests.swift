import XCTest
@testable import WaterCore

final class LocalOrderHistoryTests:XCTestCase {
    private let now=Date(timeIntervalSince1970:1_800_000_000)
    private func row(_ id:String,owner:String="a",seconds:TimeInterval=0,status:String="待核对",amount:Decimal?=nil)->LocalOrderRecord {
        .init(id:id,owner:owner,kind:"water",title:"热水",startedAt:now.addingTimeInterval(seconds),status:status,amount:amount,amountLabel:"测试")
    }
    func testWindowOwnerAndFutureFiltering() {
        let rows=[row("now"),row("boundary",seconds:-7*86400),row("tooOld",seconds:-7*86400-1),row("future",seconds:1),row("other",owner:"b")]
        XCTAssertEqual(LocalOrderRecord.recent(rows,owners:["water":"a"],now:now).map(\.id),["now","boundary"])
        XCTAssertTrue(LocalOrderRecord.recent(rows,owners:[:],now:now).isEmpty)
    }
    func testUpdatedStateReplacesSnapshotAndSurvivesSerialization() throws {
        let old=row("same"),new=row("same",status:"已结算",amount:Decimal(string:"1.23"))
        let bytes=try JSONEncoder().encode([old,new])
        let restored=try JSONDecoder().decode([LocalOrderRecord].self,from:bytes)
        XCTAssertEqual(LocalOrderRecord.recent(restored,owners:["water":"a"],now:now),[new])
    }
    func testUnsettledWaterCannotShowReceiptAsChargedAndLegacyIsUnattributed() {
        var s=WaterSession(stage:.settlementPending,machineID:"00112233",peripheralID:"radio")
        s.receipt=SettlementReceipt(payFen:123)
        XCTAssertNil(LocalOrderRecord.water(s))
        s.historyOwner="a"
        let pending=LocalOrderRecord.water(s)!
        XCTAssertNil(pending.amount)
        s.stage = .settled
        let done=LocalOrderRecord.water(s)!
        XCTAssertEqual(pending.id,done.id)
        XCTAssertEqual(done.amount,Decimal(string:"1.23"))
    }
    func testLaundryNeverUsesQuotedPriceAndKeepsIdentityAcrossReceipt() throws {
        let body:[String:Any]=["deviceId":"machine","programId":1,"programName":"普通洗","expectedPrice":9.99,"createdAt":12345,"stage":"creating","credentialIdentity":"account"]
        var record=try JSONDecoder().decode(LaundryCheckoutRecord.self,from:JSONSerialization.data(withJSONObject:body))
        let pending=LocalOrderRecord.laundry(record)!
        XCTAssertNil(pending.amount)
        record.orderId="order123"
        record.order=try JSONDecoder().decode(LaundryOrder.self,from:Data(#"{"orderId":"order123","deviceId":"machine","status":50,"payFlag":1,"payPrice":1.9}"#.utf8))
        let paid=LocalOrderRecord.laundry(record)!
        XCTAssertEqual(pending.id,paid.id)
        XCTAssertEqual(paid.amount,Decimal(string:"1.9"))
        record.credentialIdentity="other"
        XCTAssertNotEqual(LocalOrderRecord.laundry(record)?.id,paid.id)
    }
    func testLegacySessionDecodesWithoutHistoryOwner() throws {
        let json=Data(#"{"stage":"active","machineID":"00112233","peripheralID":"radio","startedAt":0}"#.utf8)
        let old=try JSONDecoder().decode(WaterSession.self,from:json)
        XCTAssertNil(old.historyOwner)
        XCTAssertNil(LocalOrderRecord.water(old))
    }
}
