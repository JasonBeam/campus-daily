import XCTest
import Foundation
@testable import Core
import CoreTestSupport

final class PaymentLaunchTests: XCTestCase {
    let price = Money(fen: 400)

    func args(_ fixture: String) throws -> PaymentArguments {
        PaymentArguments(try XCTUnwrap(try FixtureLoader.load("ujing/" + fixture).responseBodyValue?["data"]))
    }

    func launch(_ json: String, amount: Money? = Money(fen: 400)) throws -> PayLaunch {
        try PaymentLaunchPolicy.launch(for: PaymentArguments(try JSONValue.parse(json)), orderAmount: amount)
    }

    func refusal(_ json: String, amount: Money? = Money(fen: 400)) -> PaymentLaunchRefusal? {
        do { _ = try launch(json, amount: amount); return nil } catch { return error as? PaymentLaunchRefusal }
    }

    func testF2FLinkFromFixtureIsKeptVerbatim() throws {
        let a = try args("paymentArguments-f2f")
        let result = try PaymentLaunchPolicy.launch(for: a, orderAmount: price)
        XCTAssertEqual(result, .checkout(URL(string: a.data["url"]!.text!)!))
    }

    func testSignedOrderMustMatchOrderAmount() throws {
        let a = try args("paymentArguments-sdk")
        guard case .sdk(let signed) = try PaymentLaunchPolicy.launch(for: a, orderAmount: price) else { return XCTFail() }
        XCTAssertEqual(PaymentLaunchPolicy.signedOrderAmount(signed), price)
        XCTAssertThrowsError(try PaymentLaunchPolicy.launch(for: a, orderAmount: Money(fen: 350))) {
            XCTAssertEqual($0 as? PaymentLaunchRefusal, .amountMismatch)
        }
        XCTAssertThrowsError(try PaymentLaunchPolicy.launch(for: a, orderAmount: Money(fen: 500))) {
            XCTAssertEqual($0 as? PaymentLaunchRefusal, .amountMismatch)
        }
        XCTAssertThrowsError(try PaymentLaunchPolicy.launch(for: a, orderAmount: nil)) {
            XCTAssertEqual($0 as? PaymentLaunchRefusal, .unknownAmount)
        }
    }

    func testSkipPayIsQuery() throws {
        XCTAssertEqual(try PaymentLaunchPolicy.launch(for: try args("paymentArguments-skipPay"), orderAmount: price), .query)
        XCTAssertEqual(try launch(#"{"jumpToQuery":1}"#, amount: nil), .query)
        XCTAssertEqual(try launch(#"{"skipPay":"true"}"#), .query)
    }

    func testQRCheckoutAllowedOnlyOverHTTPSOnAlipayHost() throws {
        XCTAssertEqual(try launch(#"{"orderInfo":"https://qr.alipay.com/test0000"}"#), .checkout(URL(string: "https://qr.alipay.com/test0000")!))
        XCTAssertEqual(refusal(#"{"url":"http://qr.alipay.com/test0000"}"#), .disallowedLink)
        XCTAssertEqual(refusal(#"{"url":"https://qr.alipay.com.evil.example/x"}"#), .disallowedLink)
        XCTAssertEqual(refusal(#"{"url":"https://qr.alipay.com:8443/x"}"#), .disallowedLink)
        XCTAssertEqual(refusal(#"{"url":"https://user@qr.alipay.com/x"}"#), .disallowedLink)
        XCTAssertEqual(refusal(#"{"url":"https://qr.alipay.com/"}"#), .disallowedLink)
    }

    func testOtherSchemesAndHostsRefused() {
        XCTAssertEqual(refusal(#"{"url":"https://pay.example.com/checkout?amount=4.00"}"#), .disallowedLink)
        XCTAssertEqual(refusal(#"{"url":"weixin://wap/pay?prepayid=TEST"}"#), .disallowedLink)
        XCTAssertEqual(refusal(#"{"url":"alipays://platformapi/startApp?appId=20000067&url=https%3A%2F%2Fevil.example"}"#), .disallowedLink)
        XCTAssertEqual(refusal(#"{"nothing":true}"#), .unavailable)
        XCTAssertEqual(refusal(#"{"orderInfo":"method=alipay.trade.app.pay&method=alipay.trade.app.pay&biz_content=%7B%22total_amount%22%3A%224.00%22%7D"}"#), .unavailable)
        XCTAssertEqual(refusal(#"{"orderInfo":"method=alipay.trade.page.pay&biz_content=%7B%22total_amount%22%3A%224.00%22%7D"}"#), .unavailable)
    }

    func testF2FLinkVariantsRefused() throws {
        let good = try XCTUnwrap(try args("paymentArguments-f2f").data["url"]?.text)
        XCTAssertTrue(PaymentLaunchPolicy.isAllowedCheckoutURL(URL(string: good)!))
        for (from, to) in [("wx.zhinengxiyifang.cn", "wx.zhinengxiyifang.cn.evil.example"),
                           ("openauth.alipay.com", "openauth.alipay.com.evil.example"),
                           ("appId=20000042", "appId=20000067"),
                           ("followType=PUBLIC", "followType=PRIVATE"),
                           ("alipays://", "alipay://")] {
            let bad = good.replacingOccurrences(of: from, with: to)
            XCTAssertFalse(PaymentLaunchPolicy.isAllowedCheckoutURL(URL(string: bad)!), from)
        }
        XCTAssertFalse(PaymentLaunchPolicy.isAllowedCheckoutURL(URL(string: good + "&appId=20000042")!), "duplicate parameter")
    }

    func testAmountsInsideLinksMustMatch() throws {
        XCTAssertEqual(refusal(#"{"url":"https://qr.alipay.com/test0000?total_amount=5.00"}"#), .amountMismatch)
        XCTAssertEqual(try launch(#"{"url":"https://qr.alipay.com/test0000?total_amount=4.00"}"#),
                       .checkout(URL(string: "https://qr.alipay.com/test0000?total_amount=4.00")!))
        // Nested in the F2F redirect.
        let good = try XCTUnwrap(try args("paymentArguments-f2f").data["url"]?.text)
        let withAmount = good.replacingOccurrences(of: "orderId%253D", with: "amount%253D3.00%2526orderId%253D")
        XCTAssertNotEqual(withAmount, good)
        XCTAssertTrue(PaymentLaunchPolicy.isAllowedCheckoutURL(URL(string: withAmount)!))
        XCTAssertEqual(refusal(#"{"url":"\#(withAmount)"}"#), .amountMismatch)
        XCTAssertEqual(refusal(#"{"url":"https://qr.alipay.com/test0000?amount=abc"}"#), .amountMismatch)
    }
}
