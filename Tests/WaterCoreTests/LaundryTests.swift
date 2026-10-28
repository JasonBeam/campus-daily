import XCTest
@testable import WaterCore

final class LaundryTests: XCTestCase {
    private let scan = Data(#"{"code":0,"message":"","data":{"service":"washer","path":"washer/home.js","result":{"orderId":0,"deviceId":"fixture-device","macAddress":"","isSlotMachine":false,"moduleType":7,"status":0,"mobile":"","createOrderEnabled":true,"reason":"","needSync":false,"needSyncBLE":false,"deviceTypeId":11}}}"#.utf8)
    private let info = Data(#"{"code":0,"data":{"deviceId":"fixture-device","deviceNo":"example","deviceTypeName":"6.5kg波轮机","deviceWashModel":[{"additionDevices":null,"additionDryTime":null,"additionParams":[],"basePrice":190,"deadline":"","description":"适合投放衣物2/3桶，一般脏污均适用哦","hide":0,"isDefault":true,"isPromotion":0,"promotionPrice":0,"tags":["2/3桶","漂洗彻底"],"time":35,"workModelId":47,"workModelName":"普通洗"},{"additionDevices":null,"additionDryTime":null,"additionParams":[],"basePrice":170,"deadline":"","description":"适合投放衣物1/2桶，轻污衣物适用哦","hide":0,"isDefault":false,"isPromotion":0,"promotionPrice":0,"tags":["1/2桶","加速快洗"],"time":25,"workModelId":48,"workModelName":"小件洗"},{"additionDevices":null,"additionDryTime":null,"additionParams":[],"basePrice":100,"deadline":"","description":"至多3/4桶，适合手洗衣物的脱水甩干","hide":0,"isDefault":false,"isPromotion":0,"promotionPrice":0,"tags":["3/4桶","快速脱水"],"time":10,"workModelId":50,"workModelName":"单脱水"},{"additionDevices":null,"additionDryTime":null,"additionParams":[],"basePrice":220,"deadline":"","description":"适合投放衣物2/3桶，一般脏污均适用哦","hide":0,"isDefault":false,"isPromotion":0,"promotionPrice":0,"tags":["大件清洗","运动浸泡"],"time":61,"workModelId":51,"workModelName":"大件洗"}],"moduleType":7,"storeName":"测试洗衣房"},"message":""}"#.utf8)
    func testObservedProgramsAndFenConversion() throws {
        let value = try LaundryProvider.decodeEvidence(scanData:scan,infoData:info,expectedDeviceId:"fixture-device")
        XCTAssertEqual(value.moduleType,7)
        XCTAssertEqual(value.stateLabel,"空闲")
        XCTAssertEqual(value.programs.map(\.time),[35,25,10,61])
        XCTAssertEqual(value.programs.map(\.price),[Decimal(string:"1.90")!,Decimal(string:"1.70")!,1,Decimal(string:"2.20")!])
    }
    func testDifferentMachineRejected() {
        XCTAssertThrowsError(try LaundryProvider.decodeEvidence(scanData:scan,infoData:info,expectedDeviceId:"another-device"))
    }
    func testNegativePriceRejected() {
        let bad = Data(String(decoding:info,as:UTF8.self).replacingOccurrences(of:"\"basePrice\":190",with:"\"basePrice\":-1").utf8)
        XCTAssertThrowsError(try LaundryProvider.decodeEvidence(scanData:scan,infoData:bad,expectedDeviceId:"fixture-device"))
    }
    func testFailureEnvelopeCannotBecomeEmptySuccess() {
        XCTAssertThrowsError(try LaundryProvider.decodeEvidence(scanData:Data(#"{"code":401,"data":null}"#.utf8),infoData:info,expectedDeviceId:"fixture-device"))
    }
    func testMachineInUseIsNotGenericUnavailable() throws {
        let changed = Data(String(decoding:scan,as:UTF8.self).replacingOccurrences(of:"\"status\":0",with:"\"status\":1").replacingOccurrences(of:"\"createOrderEnabled\":true",with:"\"createOrderEnabled\":false").utf8)
        let value = try LaundryProvider.decodeEvidence(scanData:changed,infoData:info,expectedDeviceId:"fixture-device")
        XCTAssertEqual(value.stateLabel,"洗衣中")
        XCTAssertFalse(value.createOrderEnabled)
    }
    func testUnknownStatusNotReportedAsIdle() throws {
        let changed = Data(String(decoding:scan,as:UTF8.self).replacingOccurrences(of:"\"status\":0",with:"\"status\":99").utf8)
        let value = try LaundryProvider.decodeEvidence(scanData:changed,infoData:info,expectedDeviceId:"fixture-device")
        XCTAssertEqual(value.stateLabel,"暂不可用")
    }
}
