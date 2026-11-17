import XCTest
import Core
@testable import XiaoRiChang

/// Which way a payment goes through `AlipayBridge`: an allowed checkout link goes to the SDK's
/// interceptor as the original string first; taken over, nothing else opens; declined, the same
/// link opens outside once. An SDK callback only asks for one order read, for its own attempt.
@MainActor
final class AlipayBridgeRoutingTests: XCTestCase {
    final class FakeSDK: AlipayService {
        var takesOver = false
        var intercepted: [String] = []
        var paid: [String] = []
        var processed: [URL] = []
        var interceptCallbacks: [@Sendable () -> Void] = []
        var payCallbacks: [@Sendable () -> Void] = []
        var processCallbacks: [@Sendable () -> Void] = []
        /// Calls back before `payInterceptor` returns.
        var callBackAtOnce = false
        func payOrder(_ order: String, scheme: String, callback: @escaping @Sendable () -> Void) {
            paid.append(order); payCallbacks.append(callback)
        }
        func payInterceptor(_ url: String, scheme: String, callback: @escaping @Sendable () -> Void) -> Bool {
            intercepted.append(url); interceptCallbacks.append(callback)
            if callBackAtOnce { callback() }
            return takesOver
        }
        func processOrder(_ url: URL, callback: @escaping @Sendable () -> Void) {
            processed.append(url); processCallbacks.append(callback)
        }
    }
    final class FakeOpener: URLOpening {
        var opened: [URL] = []
        func open(_ url: URL, completion: @escaping (Bool) -> Void) { opened.append(url); completion(true) }
    }

    let qr = "https://qr.alipay.com/bax0000000000000000000099"
    var sdk: FakeSDK!
    var opener: FakeOpener!
    var bridge: AlipayBridge!

    override func setUp() async throws {
        sdk = FakeSDK(); opener = FakeOpener()
        bridge = AlipayBridge(sdk: sdk, opener: opener)
    }

    func checkout(_ link: String, returned: @escaping () -> Void = {}) async -> Bool {
        await withCheckedContinuation { done in
            bridge.openCheckout(URL(string: link)!, returned: returned) { done.resume(returning: $0) }
        }
    }

    func settle() async { for _ in 0..<5 { await Task.yield() } }

    func testTakenOverOpensNothingElse() async {
        sdk.takesOver = true
        let opened = await checkout(qr)
        XCTAssertTrue(opened)
        XCTAssertEqual(sdk.intercepted, [qr])
        XCTAssertEqual(opener.opened, [], "no web page once the SDK has it")
    }

    func testDeclinedOpensTheSameLinkOnce() async {
        let link = "https://qr.alipay.com/bax0000000000000000000099?t=1&a=b"
        let opened = await checkout(link)
        XCTAssertTrue(opened)
        XCTAssertEqual(sdk.intercepted, [link], "the original string, unchanged")
        XCTAssertEqual(opener.opened.map(\.absoluteString), [link])
    }

    func testDisallowedLinkCallsNeither() async {
        let opened = await checkout("https://example.com/pay")
        XCTAssertFalse(opened)
        XCTAssertEqual(sdk.intercepted, [])
        XCTAssertEqual(opener.opened, [])
    }

    func testCallbackAsksForOneReadOnly() async {
        sdk.takesOver = true
        var reads = 0
        _ = await checkout(qr) { reads += 1 }
        sdk.interceptCallbacks[0]()
        sdk.interceptCallbacks[0]()
        await settle()
        XCTAssertEqual(reads, 1)
    }

    func testEarlyCallbackDeliveredOnTakeover() async {
        sdk.takesOver = true; sdk.callBackAtOnce = true
        var reads = 0
        _ = await checkout(qr) { reads += 1 }
        await settle()
        XCTAssertEqual(reads, 1)
    }

    func testCallbackAfterDeclineDropped() async {
        var reads = 0
        _ = await checkout(qr) { reads += 1 }
        sdk.interceptCallbacks[0]()
        await settle()
        XCTAssertEqual(reads, 0, "the scene's own read covers the return")
    }

    /// A's SDK callback arriving after B began never reaches B.
    func testOldAttemptCallbackNotGivenToNewPayment() async {
        var a = 0, b = 0
        bridge.pay("signed-a") { a += 1 }
        bridge.pay("signed-b") { b += 1 }
        sdk.payCallbacks[0]()
        await settle()
        XCTAssertEqual(a + b, 0)
        sdk.payCallbacks[1]()
        await settle()
        XCTAssertEqual(b, 1)
    }

    /// A return URL can't say whose it is: the SDK gets it while the current attempt is the SDK's,
    /// and its result never stands for that attempt's callback.
    func testSafepayReturnNeverConsumesTheAttempt() async {
        var reads = 0
        bridge.pay("signed-a") { }
        bridge.pay("signed-b") { reads += 1 }
        let url = URL(string: AlipayBridge.scheme + "://safepay/?ResultDic=x")!
        bridge.handle(url)
        XCTAssertEqual(sdk.processed, [url])
        sdk.processCallbacks[0]()
        await settle()
        XCTAssertEqual(reads, 0)
        sdk.payCallbacks[1]()
        await settle()
        XCTAssertEqual(reads, 1, "B's own callback still goes through")
    }

    func testSafepayReturnIgnoredAfterDecline() async {
        _ = await checkout(qr)
        bridge.handle(URL(string: AlipayBridge.scheme + "://safepay/?x=1")!)
        XCTAssertEqual(sdk.processed, [])
    }
}
