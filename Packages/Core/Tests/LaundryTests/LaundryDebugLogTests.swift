import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// The TestFlight log over a laundry order: phases, request outcomes, U净's status codes and a
/// salted order tag; never the order id, the machine, the QR code or the payment link.
final class LaundryDebugLogTests: XCTestCase {
    var store: InMemorySecureStore!
    var vault: StoredLaundryVault!
    var api: FakeLaundryAPI!
    var launcher: FakeLauncher!
    var folder: URL!
    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_332_810))

    override func setUp() {
        store = InMemorySecureStore()
        vault = StoredLaundryVault(store: store)
        api = FakeLaundryAPI()
        launcher = FakeLauncher()
        folder = DebugLogTesting.temporaryDirectory()
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    let paymentURL = "alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url="
        + "https%3A%2F%2Fopenauth.alipay.com%2Foauth2%2FpublicAppAuthorize.htm%3Fredirect_uri%3Dhttps%253A%252F%252Fwx.zhinengxiyifang.cn%252Fstatic%252FcommonWasher%252Findex.html"

    var secrets: [String] {
        [L.orderID, L.device, L.qr, "000000000000000001", L.token, L.mobileID, "alipays", "openauth", "20000042",
         "测试洗衣机01", "示例洗衣房", "test-store-01", "标准洗"]
    }

    func engine(_ log: any DebugLogSink) throws -> LaundryEngine {
        try LaundryEngine(api: api, vault: vault, launcher: launcher, now: clock.function, sleep: { _ in }, debugLog: log)
    }

    func testAnOrderPaidAndWashedLeavesEveryStepAndNoValue() async throws {
        let log = FileDebugLog(directory: FileDebugLog.directory(in: folder), now: clock.function, timeZone: TimeZone(identifier: "UTC")!)
        let e = try engine(log)
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        _ = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        api.methods = [.ok([PayChannel(channel: "alipayF2F", branchType: 0)])]
        api.arguments = [.ok(PaymentArguments(.object(["url": .string(paymentURL)])))]
        _ = try await e.pay()
        api.orders = [.ok(L.order("20", remain: 1800))]
        _ = try await e.returnedFromPayment()
        api.orders = [.ok(L.order("50"))]
        let s = try await e.refresh()
        XCTAssertEqual(s.lastOutcome?.status.code, "50")

        let o = log.tag(DebugTag(.order, L.orderID))
        let bodies = log.lines().map { String($0.dropFirst(15)) }
        let expected = [
            "laundry.phase from=none to=creating",
            "laundry.request create ok",
            "laundry.phase from=creating to=created",
            "laundry.request orderDetail ok",
            "laundry.order status=10 order=\(o)",
            "laundry.request paymentMethods ok",
            "laundry.phase from=created to=paying",
            "laundry.request paymentArguments ok",
            "laundry.payLaunch opened=yes",
            "laundry.phase from=paying to=verifying",
            "laundry.order status=20 order=\(o)",
            "laundry.phase from=verifying to=active",
            "laundry.order status=50 order=\(o)",
            "laundry.phase from=active to=none last=50",
        ]
        var i = 0
        for want in expected {
            while i < bodies.count, bodies[i] != want { i += 1 }
            guard i < bodies.count else { return XCTFail("missing or out of order: \(want)\n" + bodies.joined(separator: "\n")) }
            i += 1
        }
        let all = bodies.joined(separator: "\n") + (try String(contentsOf: log.eventsFile, encoding: .utf8))
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: all), [])
        XCTAssertEqual(log.droppedCount, 0)
    }

    /// A refusal keeps U净's code and drops its sentence.
    func testARefusedRequestKeepsItsCodeOnly() async throws {
        let log = RecordingDebugLog()
        let e = try engine(log)
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        _ = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        api.methods = [.fail(.rejected(.ujing, code: "4002", message: "订单 TESTORDER0001 不能支付"))]
        _ = try? await e.pay()
        XCTAssertTrue(log.lines().contains("laundry.request paymentMethods failed kind=rejected service=ujing code=4002"),
                      log.lines().joined(separator: "\n"))
        XCTAssertEqual(DebugLogTesting.leaks(secrets + ["不能支付"], in: log.lines().joined()), [])
    }

    func testAnAlipayThatDidNotOpenIsLogged() async throws {
        let log = RecordingDebugLog()
        launcher.result = false
        let e = try engine(log)
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        _ = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        api.methods = [.ok([PayChannel(channel: "alipayF2F", branchType: 0)])]
        api.arguments = [.ok(PaymentArguments(.object(["url": .string(paymentURL)])))]
        _ = try? await e.pay()
        XCTAssertTrue(log.events.contains(.laundryPayLaunch(opened: false)))
    }

    /// 退出 U净 empties the log and drops its salt.
    func testSigningOutOfUjingClearsTheLog() throws {
        let log = RecordingDebugLog()
        let vault = StoredLaundryVault(store: InMemorySecureStore())
        try vault.saveAccountItem(UjingAccountItem(mobileID: L.mobileID, account: UjingAccount(id: "acct-1", userId: "user-1", token: L.token)))
        _ = try UjingSignOut.perform(vault: vault, preferences: UserDefaults(suiteName: UUID().uuidString)!,
                                     checkout: nil, debugLog: log)
        XCTAssertEqual(log.clears, 1)
    }

    /// A refused sign-out (an order open) leaves the log as it is.
    func testARefusedSignOutKeepsTheLog() throws {
        let log = RecordingDebugLog()
        let vault = StoredLaundryVault(store: InMemorySecureStore())
        let open = LaundryCheckout(phase: .created, orderID: L.orderID)
        XCTAssertThrowsError(try UjingSignOut.perform(vault: vault, preferences: UserDefaults(suiteName: UUID().uuidString)!,
                                                      checkout: open, debugLog: log))
        XCTAssertEqual(log.clears, 0)
    }
}
