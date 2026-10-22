import XCTest
@testable import WaterCore

private actor CheckoutAPI: LaundryOrdering {
    var createCount = 0
    var paymentCount = 0
    var cancelCount = 0
    var preparationCount = 0
    var orderStatus = "17"
    var payFlag = 0
    var cancelThrows = false
    var cancelChangesStatus = true
    var detailFailsAfterCancel = false
    var failCreate = false
    var failPayment = false
    var failDetail = false
    var wrongDevice = false
    func failures(create: Bool = false, payment: Bool = false, wrong: Bool = false, detail: Bool = false) {
        failCreate = create; failPayment = payment; wrongDevice = wrong; failDetail = detail
    }
    func create(config: LaundryConfig, snapshot: LaundrySnapshot, program: LaundryProgram) async throws -> LaundryCreatedOrder {
        createCount += 1
        if failCreate { throw LaundryError.network }
        return try JSONDecoder().decode(LaundryCreatedOrder.self,from:Data(#"{"orderId":12345}"#.utf8))
    }
    func order(config: LaundryConfig, id: String) async throws -> LaundryOrder {
        if failDetail { throw LaundryError.network }; return try makeOrder()
    }
    func payment(config: LaundryConfig, id: String) async throws -> LaundryPayment {
        paymentCount += 1
        if failPayment { throw LaundryError.network }
        return try JSONDecoder().decode(LaundryPayment.self,from:Data(#"{"skipPay":false,"jumpToQuery":true}"#.utf8))
    }
    func preparePayment(config: LaundryConfig, id: String) async { preparationCount += 1 }
    func setOrderState(status: String, payFlag: Int) { orderStatus = status; self.payFlag = payFlag }
    func setCancellation(throwsError: Bool, changesStatus: Bool = true, detailFails: Bool = false) {
        cancelThrows = throwsError; cancelChangesStatus = changesStatus; detailFailsAfterCancel = detailFails
    }
    func cancel(config: LaundryConfig, id: String) async throws {
        cancelCount += 1
        if cancelChangesStatus { orderStatus = "53" }
        if detailFailsAfterCancel { failDetail = true }
        if cancelThrows { throw LaundryError.network }
    }
    private func makeOrder() throws -> LaundryOrder {
        let device = wrongDevice ? "other" : "fixture"
        let object: [String:Any] = ["orderId":12345,"deviceId":device,"status":orderStatus,"payFlag":payFlag,
            "deviceWashModelId":47,"createAt":ISO8601DateFormatter().string(from:Date()),"payPrice":1.90]
        return try JSONDecoder().decode(LaundryOrder.self,from:JSONSerialization.data(withJSONObject:object))
    }

}
@MainActor private final class CheckoutStore: LaundryCheckoutStore {
    var record: LaundryCheckoutRecord?
    var fail = false
    func load() throws -> LaundryCheckoutRecord? { record }
    func save(_ value: LaundryCheckoutRecord) throws {
        if fail { throw LaundryError.configuration }
        record = value
    }
}

@MainActor final class LaundryCheckoutTests: XCTestCase {
    func testCreationPreparesOnlyChannelMetadataWithoutPayment() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api)
        let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        let prepared = await api.preparationCount; let payments = await api.paymentCount
        XCTAssertEqual(prepared,1); XCTAssertEqual(payments,0)
        XCTAssertEqual(c.record?.stage,.created)
    }
    private func evidence(price: Int = 190) throws -> LaundrySnapshot {
        let scan = Data(#"{"code":0,"data":{"result":{"deviceId":"fixture","moduleType":7,"status":0,"createOrderEnabled":true,"orderId":0}}}"#.utf8)
        let info = Data("{\"code\":0,\"data\":{\"deviceId\":\"fixture\",\"deviceNo\":\"test\",\"deviceTypeName\":\"test\",\"storeName\":\"test\",\"storeId\":\"store\",\"deviceTypeId\":11,\"moduleType\":7,\"deviceWashModel\":[{\"workModelId\":47,\"workModelName\":\"普通洗\",\"time\":35,\"basePrice\":\(price),\"hide\":0,\"isPromotion\":0,\"promotionPrice\":0}]}}".utf8)
        return try LaundryProvider.decodeEvidence(scanData:scan,infoData:info,expectedDeviceId:"fixture")
    }
    private func config() throws -> LaundryConfig {
        try JSONDecoder().decode(LaundryConfig.self,from:Data(#"{"headers":{"Authorization":"Bearer fake-token-only-for-unit-tests"},"qrCode":"https://q.ujing.com.cn/ucqrc/index.html?cd=example","deviceId":"fixture"}"#.utf8))
    }
    func testPersistenceFailurePreventsOrderCreation() async throws {
        let store = CheckoutStore(); store.fail = true
        let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        do { try await c.create(config:config(),snapshot:quote,program:quote.programs[0]); XCTFail() } catch {}
        let count = await api.createCount; XCTAssertEqual(count,0)
    }
    func testUncertainCreationSurvivesRestartAndCannotRepeat() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); await api.failures(create:true)
        let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        do { try await c.create(config:config(),snapshot:quote,program:quote.programs[0]); XCTFail() } catch {}
        XCTAssertEqual(store.record?.stage,.creating)
        let restarted = try LaundryCheckoutController(store:store,api:api)
        do { try await restarted.create(config:config(),snapshot:quote,program:quote.programs[0]); XCTFail() } catch {}
        let count = await api.createCount; XCTAssertEqual(count,1)
    }
    func testPriceChangedRequiresNewConfirmation() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api)
        let quote = try evidence(); let different = try evidence(price:220)
        do { try await c.create(config:config(),snapshot:quote,program:different.programs[0]); XCTFail() } catch {}
        let count = await api.createCount; XCTAssertEqual(count,0)
    }
    func testPaymentTimeoutNeverRepeatsFinancialRequest() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        await api.failures(payment:true)
        do { _ = try await c.payment(config:config()); XCTFail() } catch {}
        XCTAssertEqual(store.record?.stage,.paymentRequested)
        let restarted = try LaundryCheckoutController(store:store,api:api)
        do { _ = try await restarted.payment(config:config()); XCTFail() } catch {}
        let count = await api.paymentCount; XCTAssertEqual(count,1)
    }
    func testWrongDeviceOrderNeverReplacesOwnedOrder() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        await api.failures(wrong:true)
        do { try await c.refresh(config:config()); XCTFail() } catch {}
        XCTAssertEqual(c.record?.order?.deviceId,"fixture")
    }
    func testOrderPathRejectsInjectedQueryOrSlash() {
        XCTAssertFalse(LaundryProvider.validOrderId("123/../456"))
        XCTAssertFalse(LaundryProvider.validOrderId("123?device=other"))
        XCTAssertTrue(LaundryProvider.validOrderId("123456"))
    }
    func testPaymentAmountAndMethodAreCheckedBeforeSDKHandoff() {
        func signed(_ amount: String, method: String = "alipay.trade.app.pay") -> String {
            var parts = URLComponents()
            parts.queryItems = [URLQueryItem(name:"method",value:method),URLQueryItem(name:"biz_content",value:"{\"total_amount\":\"\(amount)\"}")]
            return parts.percentEncodedQuery!
        }
        XCTAssertTrue(LaundryPayment.validSignedOrder(signed("1.90"),maximum:Decimal(string:"1.90")!))
        XCTAssertFalse(LaundryPayment.validSignedOrder(signed("2.20"),maximum:Decimal(string:"1.90")!))
        XCTAssertFalse(LaundryPayment.validSignedOrder(signed("1.90oops"),maximum:2))
        XCTAssertFalse(LaundryPayment.validSignedOrder(signed("1.90",method:"unexpected"),maximum:2))
        XCTAssertFalse(LaundryPayment.validSignedOrder(signed("0"),maximum:2))
    }

    func testReceiptOnlyResponseKeepsOrderIDBeforeDetailFailure() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); await api.failures(detail:true)
        let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        do { try await c.create(config:config(),snapshot:quote,program:quote.programs[0]); XCTFail() } catch {}
        XCTAssertEqual(store.record?.orderId,"12345")
        XCTAssertEqual(store.record?.stage,.creating)
        await api.failures()
        let restarted = try LaundryCheckoutController(store:store,api:api)
        try await restarted.refresh(config:config())
        XCTAssertEqual(restarted.record?.stage,.created)
        let count = await api.createCount; XCTAssertEqual(count,1)
    }

    func testReceiptAcceptsMinimalAndScalarOrderID() throws {
        for text in [#"{"orderId":12345}"#,#"{"id":"12345"}"#,"12345"] {
            let receipt = try JSONDecoder().decode(LaundryCreatedOrder.self,from:Data(text.utf8))
            XCTAssertEqual(receipt.id,"12345")
        }
    }
    func testFaceToFaceURLRequiresExactHTTPSAlipayHost() throws {
        let good = try JSONDecoder().decode(LaundryPayment.self,from:Data(#"{"payInfo":{"qr_code":"https://qr.alipay.com/example"},"skipPay":0}"#.utf8))
        XCTAssertEqual(good.checkoutURL?.host,"qr.alipay.com")
        XCTAssertEqual(good.skipPay,false)
        for url in ["http://qr.alipay.com/example","https://qr.alipay.com.evil.test/example","https://evil.test/?url=https://qr.alipay.com/example"] {
            let data = try JSONSerialization.data(withJSONObject:["payInfo":["url":url]])
            XCTAssertNil(try JSONDecoder().decode(LaundryPayment.self,from:data).checkoutURL)
        }
    }

    func testFaceToFaceImmediatePaymentMatchesCurrentCashier() throws {
        let methods = try JSONDecoder().decode(LaundryPaymentMethods.self,from:Data(#"{"channels":[{"channel":"unionPay","branchType":1},{"channel":"alipayF2F","branchType":0}]}"#.utf8))
        let path = try XCTUnwrap(methods.preferred).argumentsPath(orderID:"12345")
        let items = try XCTUnwrap(URLComponents(string:path)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues:items.map { ($0.name,$0.value ?? "") })
        XCTAssertEqual(values,["channel":"alipayF2F","orderId":"12345","payVersion":"1","branchType":"0","alipayF2FNoAds":"true"])
        XCTAssertNil(values["chooseSign"])
    }

    func testStandardPaymentKeepsSDKChannelWithoutPromotionalFlag() throws {
        let methods = try JSONDecoder().decode(LaundryPaymentMethods.self,from:Data(#"{"channels":[{"channel":"alipayF2F","branchType":0},{"channel":"alipay"}]}"#.utf8))
        let path = try XCTUnwrap(methods.preferred).argumentsPath(orderID:"12345")
        XCTAssertEqual(methods.preferred?.channel,"alipay")
        XCTAssertFalse(path.contains("alipayF2FNoAds"))
        XCTAssertThrowsError(try methods.preferred?.argumentsPath(orderID:"123&chooseSign=1"))
    }

    func testQRInOrderInfoUsesCheckoutRatherThanSDK() throws {
        for object in [["orderInfo":"https://qr.alipay.com/example"], ["payInfo":["orderInfo":"https://qr.alipay.com/example"]]] as [[String:Any]] {
            let payment = try JSONDecoder().decode(LaundryPayment.self,from:JSONSerialization.data(withJSONObject:object))
            XCTAssertEqual(try payment.destination(maximum:1),.checkout(URL(string:"https://qr.alipay.com/example")!))
        }
    }

    func testInvalidPaymentCannotBeLaunchedAndQueryDoesNotLaunchCheckout() throws {
        let bad = try JSONDecoder().decode(LaundryPayment.self,from:Data(#"{"orderInfo":"https://evil.test/pay"}"#.utf8))
        XCTAssertThrowsError(try bad.destination(maximum:1))
        let query = try JSONDecoder().decode(LaundryPayment.self,from:Data(#"{"skipPay":true,"orderInfo":"https://qr.alipay.com/example"}"#.utf8))
        XCTAssertEqual(try query.destination(maximum:1),.query)
    }

    private func faceToFaceLink(authHost: String = "openauth.alipay.com", redirectHost: String = "wx.zhinengxiyifang.cn", appID: String = "20000042", duplicateURL: Bool = false) -> URL {
        var auth = URLComponents(); auth.scheme = "https"; auth.host = authHost; auth.path = "/oauth2/publicAppAuthorize.htm"
        auth.queryItems = [URLQueryItem(name:"app_id",value:"0000000000000000"),URLQueryItem(name:"state",value:"fixture-state"),URLQueryItem(name:"redirect_uri",value:"https://\(redirectHost)/static/commonWasher/index.html"),URLQueryItem(name:"orderId",value:"12345")]
        var link = URLComponents(); link.scheme = "alipays"; link.host = "platformapi"; link.path = "/startApp"
        link.queryItems = [URLQueryItem(name:"appId",value:appID),URLQueryItem(name:"publicId",value:"0000000000000000"),URLQueryItem(name:"followType",value:"PUBLIC"),URLQueryItem(name:"actionType",value:"WebView"),URLQueryItem(name:"url",value:auth.string!)]
        if duplicateURL { link.queryItems?.append(URLQueryItem(name:"url",value:"https://evil.test")) }
        return link.url!
    }

    func testObservedF2FDeepLinkPreservesOpaqueParameters() throws {
        let url = faceToFaceLink()
        let data = try JSONSerialization.data(withJSONObject:["url":url.absoluteString])
        let payment = try JSONDecoder().decode(LaundryPayment.self,from:data)
        XCTAssertEqual(try payment.destination(maximum:1),.checkout(url))
        XCTAssertEqual(payment.checkoutURL?.absoluteString,url.absoluteString)
    }

    func testF2FDeepLinkRejectsOtherAppsHostsRedirectsAndDuplicateURL() {
        for url in [faceToFaceLink(authHost:"openauth.alipay.com.evil.test"),faceToFaceLink(redirectHost:"evil.test"),faceToFaceLink(appID:"other"),faceToFaceLink(duplicateURL:true),URL(string:"alipays://platformapi/startApp?appId=20000042")!] {
            XCTAssertFalse(LaundryPayment.isAllowedCheckoutURL(url))
        }
    }

    func testRecoveryMatchesExistingReservationWithoutCreatingAgain() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); await api.failures(create:true)
        let controller = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        do { try await controller.create(config:config(),snapshot:quote,program:quote.programs[0]); XCTFail() } catch {}
        await api.failures()
        try await controller.recover(config:config(),candidateOrderId:"12345")
        XCTAssertEqual(controller.record?.orderId,"12345")
        XCTAssertEqual(controller.record?.stage,.created)
        let count = await api.createCount; XCTAssertEqual(count,1)
    }
    func testRecoveryRejectsOrderFromAnotherMachine() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); await api.failures(create:true)
        let controller = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        do { try await controller.create(config:config(),snapshot:quote,program:quote.programs[0]); XCTFail() } catch {}
        await api.failures(wrong:true)
        do { try await controller.recover(config:config(),candidateOrderId:"12345"); XCTFail() } catch {}
        XCTAssertNil(controller.record?.orderId)
        XCTAssertEqual(controller.record?.stage,.creating)
    }

    func testUnpaidReservationCancellationIsVerifiedWithServer() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        try await c.cancel(config:config())
        XCTAssertEqual(c.record?.stage,.completed)
        XCTAssertEqual(c.record?.order?.status.text,"53")
        let count = await api.cancelCount; XCTAssertEqual(count,1)
    }
    func testCancellationRechecksPaymentAndDoesNotCancelPaidOrder() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        await api.setOrderState(status:"20",payFlag:1)
        do { try await c.cancel(config:config()); XCTFail() } catch {}
        let count = await api.cancelCount; XCTAssertEqual(count,0)
        XCTAssertEqual(c.record?.order?.paid,true)
    }
    func testPersistenceFailurePreventsCancellationRequest() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0]); store.fail = true
        do { try await c.cancel(config:config()); XCTFail() } catch {}
        let count = await api.cancelCount; XCTAssertEqual(count,0)
    }
    func testCancellationTimeoutReconcilesWithoutRepeatingPOST() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        await api.setCancellation(throwsError:true)
        try await c.cancel(config:config())
        XCTAssertEqual(c.record?.stage,.completed)
        let count = await api.cancelCount; XCTAssertEqual(count,1)
    }
    func testUnknownCancellationSurvivesRestartAndBlocksDuplicate() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        await api.setCancellation(throwsError:true,changesStatus:false,detailFails:true)
        do { try await c.cancel(config:config()); XCTFail() } catch {}
        XCTAssertEqual(store.record?.stage,.cancellationRequested)
        let restarted = try LaundryCheckoutController(store:store,api:api)
        do { try await restarted.cancel(config:config()); XCTFail() } catch {}
        let count = await api.cancelCount; XCTAssertEqual(count,1)
    }
    func testCancelDoesNotRepeatAlreadyCompletedReservation() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        await api.setOrderState(status:"53",payFlag:0)
        try await c.cancel(config:config())
        XCTAssertEqual(c.record?.stage,.completed)
        let count = await api.cancelCount; XCTAssertEqual(count,0)
    }

    func testUnpaidReservationCanBeCancelledAfterFailedPaymentLaunch() async throws {
        let store = CheckoutStore(); let api = CheckoutAPI(); let c = try LaundryCheckoutController(store:store,api:api); let quote = try evidence()
        try await c.create(config:config(),snapshot:quote,program:quote.programs[0])
        await api.failures(payment:true)
        do { _ = try await c.payment(config:config()); XCTFail() } catch {}
        XCTAssertEqual(c.record?.stage,.paymentRequested)
        try await c.cancel(config:config())
        XCTAssertEqual(c.record?.stage,.completed)
        let count = await api.cancelCount; XCTAssertEqual(count,1)
    }

}
