import XCTest
@testable import WaterCore

@MainActor final class LaundrySDKConversionTests: XCTestCase {
    func testEarlyCallbackIsBufferedUntilConversionIsAccepted() {
        var statuses: [String] = []
        let attempt = LaundrySDKConversion { status,_ in statuses.append(status) }
        attempt.receive(status:"9000",memo:"")
        XCTAssertTrue(statuses.isEmpty)
        attempt.resolve(converted:true)
        XCTAssertEqual(statuses,["9000"])
        attempt.receive(status:"9000",memo:"")
        XCTAssertEqual(statuses.count,1)
    }
    func testRejectedConversionNeverDeliversEarlyOrLateSDKResults() {
        var callbacks = 0
        let attempt = LaundrySDKConversion { _,_ in callbacks += 1 }
        attempt.receive(status:"9000",memo:"")
        attempt.resolve(converted:false)
        attempt.receive(status:"9000",memo:"")
        attempt.resolve(converted:true)
        XCTAssertEqual(callbacks,0)
    }
    func testAcceptedSDKFailureStaysOnSDKFlowAndDeliversOnce() {
        var statuses: [String] = []
        let attempt = LaundrySDKConversion { status,_ in statuses.append(status) }
        attempt.resolve(converted:true)
        attempt.resolve(converted:false)
        attempt.receive(status:"4000",memo:"fixture failure")
        attempt.receive(status:"9000",memo:"")
        XCTAssertEqual(statuses,["4000"])
    }
    func testBothSDKResultFormatsAreRecognizedWithoutTrustingReturnURL() {
        XCTAssertEqual(LaundrySDKResult(["resultStatus":"9000"]).status,"9000")
        XCTAssertEqual(LaundrySDKResult(["resultCode":9000]).status,"9000")
        XCTAssertEqual(LaundrySDKResult(["resultCode":"6001","memo":"cancel"]).memo,"cancel")
        XCTAssertEqual(LaundrySDKResult(["returnUrl":"https://example.invalid/success"]).status,"unknown")
    }
    private func appOrder(sign: String? = "offline-fixture", amount: String = "1.90") -> String {
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name:"method",value:"alipay.trade.app.pay"),URLQueryItem(name:"biz_content",value:"{\"total_amount\":\"\(amount)\"}")]
        if let sign { parts.queryItems?.append(URLQueryItem(name:"sign",value:sign)) }
        return parts.percentEncodedQuery!
    }
    func testAppPaymentTakesPrecedenceOverWebCheckoutWhenBothAreIssued() throws {
        let signed = appOrder()
        let data = try JSONSerialization.data(withJSONObject:["orderInfo":signed,"url":"https://qr.alipay.com/offline-fixture"])
        let payment = try JSONDecoder().decode(LaundryPayment.self,from:data)
        XCTAssertEqual(try payment.destination(maximum:2),.sdk(signed))
    }
    func testUnsignedOrWrongAmountAppStringCannotDisplaceOfficialCheckout() throws {
        for signed in [appOrder(sign:nil),appOrder(sign:""),appOrder(amount:"3.00")] {
            let data = try JSONSerialization.data(withJSONObject:["orderInfo":signed,"url":"https://qr.alipay.com/offline-fixture"])
            let payment = try JSONDecoder().decode(LaundryPayment.self,from:data)
            XCTAssertEqual(try payment.destination(maximum:2),.checkout(URL(string:"https://qr.alipay.com/offline-fixture")!))
        }
    }
}
