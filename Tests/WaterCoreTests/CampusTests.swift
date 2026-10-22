import Foundation
import Testing
@testable import WaterCore

@Suite struct CampusTests {
    @Test func parsesNumericAndObjectBalances() throws {
        #expect(try CampusParser.balance("25.80") == Decimal(string:"25.80"))
        #expect(try CampusParser.balance(["balance":12.5]) == Decimal(string:"12.5"))
        #expect(try CampusParser.balance(0) == 0)
        #expect(try CampusParser.balance("-1.50") == Decimal(string:"-1.50"))
    }
    @Test func rejectsMissingMalformedAndBooleanAmounts() {
        for value:Any in [true,NSNull(),"", "NaN","2.5junk","1,000",Double.infinity] {
            #expect(throws:CampusError.response) { try CampusParser.balance(value) }
        }
    }
    @Test func resolvesSingleRoomButNeverChoosesBetweenDorms() throws {
        #expect(try CampusParser.room([["piplineName":"测试楼-101"]]) == "测试楼-101")
        #expect(try CampusParser.room(["roomName":"102"]) == "102")
        #expect(throws:CampusError.ambiguous) { try CampusParser.room([["roomName":"101"],["roomName":"102"]]) }
        #expect(throws:CampusError.response) { try CampusParser.room(["roomName":""]) }
    }
    @Test func preservesBalanceAndTimestampOnFailure() {
        var value = CampusSnapshot(owner:"test")
        let original = Date(timeIntervalSince1970:1000)
        value.recordBalance(.success(Decimal(string:"25.80")!),at:original)
        value.recordBalance(.failure(.expired),at:Date(timeIntervalSince1970:2000))
        #expect(value.balance == Decimal(string:"25.80"))
        #expect(value.balanceFetchedAt == original)
        #expect(value.balanceIsStale(at:Date(timeIntervalSince1970:1100)))
    }
    @Test func cardAndRoomFailuresAreIndependent() {
        var value = CampusSnapshot(owner:"test")
        value.recordBalance(.success(12))
        value.recordRoom(.failure(.network))
        #expect(value.balance == 12 && !value.balanceIsStale())
        #expect(value.room == nil)
    }
    @Test func staleTimeAndFutureTimeAreLabelled() {
        var value = CampusSnapshot(owner:"test")
        let time = Date(timeIntervalSince1970:1000)
        value.recordBalance(.success(12),at:time)
        #expect(!value.balanceIsStale(at:Date(timeIntervalSince1970:1100)))
        #expect(value.balanceIsStale(at:Date(timeIntervalSince1970:2500)))
        #expect(value.balanceIsStale(at:Date(timeIntervalSince1970:900)))
    }
    @Test func decodesExistingConfigurationAndScopesCacheToIdentity() throws {
        let raw = Data(#"{"syscustid":"test-user","acc_token":"test-token","buildingID":"123"}"#.utf8)
        let config = try JSONDecoder().decode(CampusConfig.self,from:raw)
        try config.validate()
        #expect(config.areacode == "450010" && config.custid.isEmpty)
        var changed = config; changed.syscustid = "another-user"
        #expect(changed.cacheIdentity != config.cacheIdentity)
        changed = config; changed.accToken = "new-token"
        #expect(changed.cacheIdentity == config.cacheIdentity)
    }
    @Test func unwrapsJSONStringDataAndRejectsFailedResponse() throws {
        let data = Data(#"{"code":0,"data":"{\"balance\":\"25.80\"}"}"#.utf8)
        #expect(try CampusParser.balance(CampusParser.unwrap(data)) == Decimal(string:"25.80"))
        #expect(throws:CampusError.expired) { try CampusParser.unwrap(Data(#"{"code":401,"data":null}"#.utf8)) }
        #expect(throws:CampusError.response) { try CampusParser.unwrap(Data(#"{"code":false,"data":0}"#.utf8)) }
    }
}
