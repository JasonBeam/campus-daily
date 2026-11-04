import XCTest
@testable import WaterCore

private actor ImmediateAPI: LaundryOrdering {
    var startCount = 0
    var status = "20"
    var paid = 1
    var module = 7
    var detailsStatus = "20"
    var requiresClean = false
    var throwStart = false
    var enterRunning = true
    var wrongDetails = false
    var calls: [String] = []
    func setup(status: String = "20", paid: Int = 1, module: Int = 7, detailsStatus: String? = nil, clean: Bool = false, fail: Bool = false, running: Bool = true, wrong: Bool = false) {
        self.status = status; self.paid = paid; self.module = module; self.detailsStatus = detailsStatus ?? status
        requiresClean = clean; throwStart = fail; enterRunning = running; wrongDetails = wrong
    }
    func data(status: String, wrong: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject:["orderId":12345,"deviceId":wrong ? "other" : "fixture","status":status,"payFlag":paid,"deviceWashModelId":47,"payPrice":1.90,"moduleType":module,"online":1,"selfCleanEnable":requiresClean,"selfCleanPrice":requiresClean ? 1 : 0])
    }
    func create(config: LaundryConfig, snapshot: LaundrySnapshot, program: LaundryProgram) async throws -> LaundryCreatedOrder { throw LaundryError.response }
    func payment(config: LaundryConfig, id: String) async throws -> LaundryPayment { throw LaundryError.response }
    func cancel(config: LaundryConfig, id: String) async throws { XCTFail("must not cancel") }
    func order(config: LaundryConfig, id: String) async throws -> LaundryOrder {
        calls.append("order")
        return try JSONDecoder().decode(LaundryOrder.self,from:data(status:status))
    }
    func startDetails(config: LaundryConfig, id: String) async throws -> LaundryStartDetails {
        calls.append("details")
        return try JSONDecoder().decode(LaundryStartDetails.self,from:data(status:detailsStatus,wrong:wrongDetails))
    }
    func startWasher(config: LaundryConfig, id: String) async throws {
        startCount += 1
        calls.append("start")
        if throwStart { throw LaundryError.network }
        if enterRunning { status = "40" }
    }
}
@MainActor private final class ImmediateStore: LaundryCheckoutStore {
    var value: LaundryCheckoutRecord?
    var rejectAttempt = false
    func load() throws -> LaundryCheckoutRecord? { value }
    func save(_ next: LaundryCheckoutRecord) throws {
        if rejectAttempt && next.startAttempt == .requested { throw LaundryError.configuration }
        value = next
    }
}
@MainActor final class LaundryImmediateStartTests: XCTestCase {
    private func fixture(armed: Bool? = true, age: TimeInterval = 0) throws -> (LaundryConfig, ImmediateStore, ImmediateAPI, LaundryCheckoutController) {
        let config = LaundryConfig(headers:["Authorization":"Bearer fake-only-for-unit-testing"],qrCode:"https://q.ujing.com.cn/ucqrc/index.html?cd=123456789012345678",deviceId:"fixture")
        let store = ImmediateStore(); let api = ImmediateAPI()
        var record = LaundryCheckoutRecord(deviceId:"fixture",programId:47,programName:"普通洗",expectedPrice:1.90,createdAt:Date().addingTimeInterval(-age),stage:.paymentRequested)
        record.orderId = "12345"; record.credentialIdentity = config.credentialIdentity; record.immediateStart = armed
        store.value = record
        return (config,store,api,try LaundryCheckoutController(store:store,api:api))
    }
    func testPaidWaitingOrderStartsAndConfirmsOnce() async throws {
        let (config,store,api,c) = try fixture()
        try await c.refresh(config:config); try await c.refresh(config:config)
        let count = await api.startCount
        XCTAssertEqual(count,1); XCTAssertEqual(store.value?.startAttempt,.confirmed); XCTAssertEqual(c.record?.order?.status.text,"40")
    }
    func testSingleFreshReadBeforeStartInsteadOfTwoSerialQueries() async throws {
        let (config,_,api,c) = try fixture()
        try await c.refresh(config:config)
        let calls = await api.calls
        XCTAssertEqual(calls,["details","start","order"])
    }
    func testShortForegroundBurstAndUncertainCommandContinueReadOnlyPolling() async throws {
        let (config,store,api,c) = try fixture()
        let now = Date()
        XCTAssertEqual(LaundryImmediatePolling.interval(store.value,activeSince:now,now:now),1)
        XCTAssertEqual(LaundryImmediatePolling.interval(store.value,activeSince:now.addingTimeInterval(-21),now:now),3)
        await api.setup(fail:true)
        try await c.refresh(config:config)
        XCTAssertTrue(LaundryImmediatePolling.needed(store.value))
        try await c.refresh(config:config)
        let count = await api.startCount; XCTAssertEqual(count,1)
        let (_,normal,_,_) = try fixture(armed:nil)
        XCTAssertEqual(LaundryImmediatePolling.interval(normal.value,activeSince:now,now:now),30)
    }
    func testNormalOldUnpaidAndAlreadyRunningOrdersDoNotStart() async throws {
        for (armed,status,paid) in [(nil as Bool?,"20",1),(false,"20",1),(true,"17",0),(true,"40",1),(true,"21",1),(true,"50",1)] {
            let (config,_,api,c) = try fixture(armed:armed)
            await api.setup(status:status,paid:paid)
            try await c.refresh(config:config)
            let count = await api.startCount; XCTAssertEqual(count,0)
        }
    }
    func testUncertainCommandDoesNotReplayAfterRelaunch() async throws {
        let (config,store,api,c) = try fixture()
        await api.setup(fail:true)
        try await c.refresh(config:config)
        let restored = try LaundryCheckoutController(store:store,api:api)
        try await restored.refresh(config:config)
        let count = await api.startCount; XCTAssertEqual(count,1); XCTAssertEqual(restored.record?.startAttempt,.requested)
    }
    func testAcceptedButStillWaitingDoesNotReplay() async throws {
        let (config,_,api,c) = try fixture()
        await api.setup(running:false)
        try await c.refresh(config:config); try await c.refresh(config:config)
        let count = await api.startCount; XCTAssertEqual(count,1); XCTAssertEqual(c.record?.startAttempt,.accepted)
    }
    func testSaveFailureBeforeCommandPreventsStart() async throws {
        let (config,store,api,c) = try fixture(); store.rejectAttempt = true
        do { try await c.refresh(config:config); XCTFail("must fail before side effect") } catch {}
        let count = await api.startCount; XCTAssertEqual(count,0); XCTAssertNil(c.record?.startAttempt)
    }
    func testWrongMachineOrChangedServerStatePreventsStart() async throws {
        for wrong in [true,false] {
            let (config,_,api,c) = try fixture()
            await api.setup(detailsStatus:wrong ? "20" : "40",wrong:wrong)
            do { try await c.refresh(config:config) } catch {}
            let count = await api.startCount; XCTAssertEqual(count,0)
        }
    }
    func testUnsupportedMachineSelfCleanAndExpiredIntentAreBlocked() async throws {
        for (module,clean,age) in [(1,false,0.0),(7,true,0.0),(7,false,601.0)] {
            let (config,_,api,c) = try fixture(age:age)
            await api.setup(module:module,clean:clean)
            try await c.refresh(config:config)
            let count = await api.startCount; XCTAssertEqual(count,0); XCTAssertEqual(c.record?.startAttempt,.blocked)
        }
    }
    func testAccountMismatchPreventsReadAndStart() async throws {
        let (config,_,api,c) = try fixture()
        let other = LaundryConfig(headers:["Authorization":"Bearer other-account-test-token"],qrCode:config.qrCode,deviceId:config.deviceId)
        do { try await c.refresh(config:other); XCTFail("must reject account") } catch {}
        let count = await api.startCount; XCTAssertEqual(count,0)
    }
    func testLegacyRecordNeverInheritsImmediateIntent() throws {
        let (_,store,_,_) = try fixture()
        let data = try JSONEncoder().encode(store.value!)
        var obj = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        obj.removeValue(forKey:"immediateStart")
        let decoded = try JSONDecoder().decode(LaundryCheckoutRecord.self,from:JSONSerialization.data(withJSONObject:obj))
        XCTAssertNil(decoded.immediateStart); XCTAssertNil(decoded.startAttempt)
    }
    func testOfficialPathAndDispenserPreparation() throws {
        XCTAssertEqual(try LaundryProvider.immediateOrderPath(id:"12345",control:true),"/api/v1/app/orders/12345/control/start")
        XCTAssertThrowsError(try LaundryProvider.immediateOrderPath(id:"../old",control:true))
        let bytes = Data(#"{"orderId":12345,"deviceId":"fixture","status":"20","payFlag":1,"moduleType":"7","online":"1","wp_order":{}}"#.utf8)
        let detail = try JSONDecoder().decode(LaundryStartDetails.self,from:bytes)
        XCTAssertEqual(detail.moduleType,7); XCTAssertEqual(detail.online,true); XCTAssertTrue(detail.requiresSelfClean)
    }
}
