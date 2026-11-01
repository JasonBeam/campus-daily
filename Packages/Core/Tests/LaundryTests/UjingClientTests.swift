import XCTest
import Foundation
@testable import Core
import CoreTestSupport

final class UjingClientTests: XCTestCase {
    func unauthorized(_ server: StubServer, _ method: String, _ path: String) throws {
        let f = try FixtureLoader.load("ujing/orderDetail-badAuth")
        server.respond(method, L.base + path, status: 401, body: f.responseBody, times: 1)
    }

    // MARK: SMS login

    func testRequestSMSSendsLoginHeadersOnly() async throws {
        let server = StubServer()
        try server.serve("ujing/captcha-ok")
        try await L.client(server, token: nil).requestSMS(mobile: "13800000000")
        let r = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.queryItem("mobile"), "13800000000")
        XCTAssertEqual(r.queryItem("type"), "1")
        XCTAssertEqual(r.header("x-app-code"), "ZI")
        XCTAssertEqual(r.header("x-app-version"), "2.4.18")
        XCTAssertEqual(r.header("x-mobile-id"), L.mobileID)
        XCTAssertEqual(r.header("x-mobile-brand"), "apple")
        XCTAssertNil(r.header("Authorization"))
        XCTAssertTrue(server.unmatched.isEmpty)
    }

    /// Regression: the app once generated a dash-less id, which the client's own check rejected,
    /// so the SMS request never left the phone. The default id must pass that check.
    func testDefaultMobileIDIsADashedUUIDTheClientAccepts() async throws {
        let vault = StoredLaundryVault(store: InMemorySecureStore())
        let id = try vault.mobileID()
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(try vault.mobileID(), id)
        let server = StubServer()
        try server.serve("ujing/captcha-ok")
        let ok = UjingClient(http: server.makeClient(allowedHosts: AllowedHosts.laundry, log: RecordingLogSink()),
                             device: UjingDevice(mobileID: id, userAgent: "XiaoRiChang/test"), token: nil)
        try await ok.requestSMS(mobile: "13800000000")
        XCTAssertEqual(server.requests.first?.header("x-mobile-id"), id)
        let dashless = UjingClient(http: server.makeClient(allowedHosts: AllowedHosts.laundry, log: RecordingLogSink()),
                                   device: UjingDevice(mobileID: id.replacingOccurrences(of: "-", with: ""), userAgent: "XiaoRiChang/test"), token: nil)
        await L.expectError(.badRequest(.ujing)) { try await dashless.requestSMS(mobile: "13800000000") }
    }

    func testRequestSMSRefusedMalformedUncertainAndBadInput() async throws {
        let server = StubServer()
        try server.serve("ujing/captcha-refused", times: 1)
        let c = L.client(server, token: nil)
        await L.expectError(.rejected(.ujing, code: "10003", message: "验证码发送过于频繁，请稍后再试")) { try await c.requestSMS(mobile: "13800000000") }
        // Sending an SMS is state-changing: an unreadable or lost reply is uncertain.
        server.respond("GET", L.base + UjingEndpoints.captcha, body: L.json(#"{"message":"ok"}"#), times: 1)
        await L.expectError(.uncertain(.ujing)) { try await c.requestSMS(mobile: "13800000000") }
        server.fail("GET", L.base + UjingEndpoints.captcha, with: .timedOut, times: 1)
        await L.expectError(.uncertain(.ujing)) { try await c.requestSMS(mobile: "13800000000") }
        let before = server.requests.count
        await L.expectError(.badRequest(.ujing)) { try await c.requestSMS(mobile: "not-a-phone") }
        await L.expectError(.badRequest(.ujing)) { try await c.requestSMS(mobile: "2380000000") }
        XCTAssertEqual(server.requests.count, before)
    }

    func testLoginReturnsAccount() async throws {
        let server = StubServer()
        try server.serve("ujing/login-ok")
        let account = try await L.client(server, token: nil).login(mobile: "13800000000", code: "123456")
        XCTAssertEqual(account, UjingAccount(id: "10001", userId: "20002", token: L.token))
        XCTAssertFalse("\(account)".contains(L.token))
        let r = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.bodyJSON, .object(["mobile": .string("13800000000"), "captcha": .string("123456")]))
        XCTAssertEqual(r.header("x-app-code"), "ZI")
        XCTAssertNil(r.header("Authorization"))
    }

    func testLoginTempTokenChallengeRefusedMalformed() async throws {
        let server = StubServer()
        let c = L.client(server, token: nil)
        let verify = ServiceError.rejected(.ujing, code: "verification", message: UjingClient.verificationMessage)
        try server.serve("ujing/login-tempToken", times: 1)
        await L.expectError(verify) { _ = try await c.login(mobile: "13800000000", code: "123456") }
        try server.serve("ujing/login-challenge", times: 1)
        await L.expectError(verify) { _ = try await c.login(mobile: "13800000000", code: "123456") }
        try server.serve("ujing/login-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "20001", message: "验证码错误或已过期")) { _ = try await c.login(mobile: "13800000000", code: "123456") }

        let ok = try FixtureLoader.load("ujing/login-ok")
        var data = try XCTUnwrap(ok.responseBodyValue?["data"]?.object)
        data["token"] = nil
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        await L.expectError(.malformed(.ujing, "data.token")) { _ = try await c.login(mobile: "13800000000", code: "123456") }
        data["token"] = .string(L.token); data["id"] = .bool(true)
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        await L.expectError(.malformed(.ujing, "data.id")) { _ = try await c.login(mobile: "13800000000", code: "123456") }

        let before = server.requests.count
        await L.expectError(.badRequest(.ujing)) { _ = try await c.login(mobile: "13800000000", code: "12") }
        XCTAssertEqual(server.requests.count, before)
    }

    // MARK: Machines

    func testScanDecodesAndUsesAuthenticatedHeaders() async throws {
        let server = StubServer()
        try server.serve("ujing/scanWasherCode-ok", times: 1)
        let c = L.client(server)
        let scan = try await c.scan(qr: L.qr)
        XCTAssertEqual(scan, WasherScan(deviceID: L.device, moduleType: 7, status: 0, createOrderEnabled: true, activeOrderID: nil))
        let r = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(r.header("Authorization"), "Bearer " + L.token)
        XCTAssertEqual(r.header("x-app-code"), "BI")
        XCTAssertEqual(r.header("x-mobile-id"), L.mobileID)
        XCTAssertEqual(r.bodyField("qrCode"), L.qr)

        try server.serve("ujing/scanWasherCode-activeOrder", times: 1)
        let busy = try await c.scan(qr: L.qr)
        XCTAssertEqual(busy.activeOrderID, L.orderID)
        XCTAssertEqual(busy.status, 11)
    }

    func testScanExpiredRefusedMalformedAndBadQR() async throws {
        let server = StubServer()
        let c = L.client(server)
        try server.serve("ujing/scanWasherCode-badAuth", times: 1)
        await L.expectError(.sessionExpired(.ujing)) { _ = try await c.scan(qr: L.qr) }
        try server.serve("ujing/scanWasherCode-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "40004", message: "设备不存在或已下线")) { _ = try await c.scan(qr: L.qr) }
        let ok = try FixtureLoader.load("ujing/scanWasherCode-ok")
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(["result": .object(["deviceId": .string(L.device), "moduleType": .int(7), "status": .int(0)])])])), times: 1)
        await L.expectError(.malformed(.ujing, "data.result.createOrderEnabled")) { _ = try await c.scan(qr: L.qr) }
        server.respond("POST", L.base + UjingEndpoints.scan, body: L.json("<html>"), times: 1)
        await L.expectError(.malformed(.ujing, "$")) { _ = try await c.scan(qr: L.qr) }
        // Envelope 401/403 also means the token is dead.
        server.respond("POST", L.base + UjingEndpoints.scan, body: L.json(#"{"code":403,"message":"forbidden"}"#), times: 1)
        await L.expectError(.sessionExpired(.ujing)) { _ = try await c.scan(qr: L.qr) }
        let before = server.requests.count
        await L.expectError(.badRequest(.ujing)) { _ = try await c.scan(qr: "https://example.com/?cd=000000000000000001") }
        await L.expectError(.badRequest(.ujing)) { _ = try await c.scan(qr: "https://q.ujing.com.cn/ucqrc/index.html?cd=1&cd=2") }
        XCTAssertEqual(server.requests.count, before)
    }

    func testProgramsDropHiddenAndUsePromotionPrice() async throws {
        let server = StubServer()
        try server.serve("ujing/programInfo-ok")
        let info = try await L.client(server).programs(deviceID: L.device)
        XCTAssertEqual(info.programs.map(\.id), [1, 2, 50])
        XCTAssertEqual(info.programs[0], L.standard)
        XCTAssertEqual(info.programs[1].price, Money(fen: 250))
        XCTAssertEqual(info.storeID, "test-store-01")
        XCTAssertEqual(info.deviceTypeID, 1)
        XCTAssertEqual(server.requests.first?.queryItem("deviceId"), L.device)
    }

    func testProgramsExpiredRefusedMalformed() async throws {
        let server = StubServer()
        let c = L.client(server)
        // Captured reply: no token at all → 401 "JWT token is missing".
        try server.serve("ujing/programInfo-noAuth", times: 1)
        await L.expectError(.sessionExpired(.ujing)) { _ = try await c.programs(deviceID: "0") }
        try server.serve("ujing/programInfo-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "40004", message: "设备不存在或已下线")) { _ = try await c.programs(deviceID: L.device) }
        let ok = try FixtureLoader.load("ujing/programInfo-ok")
        var data = try XCTUnwrap(ok.responseBodyValue?["data"]?.object)
        var rows = try XCTUnwrap(data["deviceWashModel"]?.array)
        var first = try XCTUnwrap(rows[0].object); first["time"] = .int(0); rows[0] = .object(first)
        data["deviceWashModel"] = .array(rows)
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        await L.expectError(.malformed(.ujing, "data.deviceWashModel[0].time")) { _ = try await c.programs(deviceID: L.device) }
        data["deviceId"] = .string("other")
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        await L.expectError(.malformed(.ujing, "data.deviceId")) { _ = try await c.programs(deviceID: L.device) }
    }

    func testWasherSnapshotCombinesScanAndPrograms() async throws {
        let server = StubServer()
        try server.serve("ujing/scanWasherCode-ok")
        try server.serve("ujing/programInfo-ok")
        let s = try await L.client(server).washer(qr: L.qr, now: L.t0)
        XCTAssertTrue(s.isOrderable)
        XCTAssertEqual(s.stateLabel, "空闲")
        XCTAssertNotNil(LaundryDraft.make(s, program: L.standard, now: L.t0.addingTimeInterval(30)))
        XCTAssertNil(LaundryDraft.make(s, program: L.standard, now: L.t0.addingTimeInterval(61)), "stale snapshot")
        XCTAssertNil(LaundryDraft.make(s, program: WasherProgram(id: 1, name: "标准洗", minutes: 45, price: Money(fen: 300)), now: L.t0), "price changed")
    }

    // MARK: Orders

    func testCreateOrderSendsBodyOnceAndReturnsID() async throws {
        let server = StubServer()
        try server.serve("ujing/orderCreate-ok")
        let id = try await L.client(server).createOrder(L.draft.request)
        XCTAssertEqual(id, L.orderID)
        let fixture = try FixtureLoader.load("ujing/orderCreate-ok")
        XCTAssertEqual(server.requests.first?.bodyJSON, fixture.requestBody)
        XCTAssertEqual(server.requests.count, 1)
    }

    func testCreateOrderOutcomes() async throws {
        let server = StubServer()
        let c = L.client(server)
        try server.serve("ujing/orderCreate-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "30010", message: "设备正在使用中，请稍后再试")) { _ = try await c.createOrder(L.draft.request) }
        try server.serve("ujing/orderCreate-badAuth", times: 1)
        await L.expectError(.sessionExpired(.ujing)) { _ = try await c.createOrder(L.draft.request) }
        server.fail("POST", L.base + UjingEndpoints.create, with: .timedOut, times: 1)
        await L.expectError(.uncertain(.ujing)) { _ = try await c.createOrder(L.draft.request) }
        server.fail("POST", L.base + UjingEndpoints.create, with: .notConnectedToInternet, times: 1)
        await L.expectError(.uncertain(.ujing)) { _ = try await c.createOrder(L.draft.request) }
        server.respond("POST", L.base + UjingEndpoints.create, status: 502, body: L.json("bad gateway"), times: 1)
        await L.expectError(.uncertain(.ujing)) { _ = try await c.createOrder(L.draft.request) }
        server.respond("POST", L.base + UjingEndpoints.create, body: L.json(#"{"code":0,"data":{}}"#), times: 1)
        await L.expectError(.uncertain(.ujing)) { _ = try await c.createOrder(L.draft.request) }
        server.respond("POST", L.base + UjingEndpoints.create, body: L.json(#"{"code":0,"data":"ABC123"}"#), times: 1)
        let scalar = try await c.createOrder(L.draft.request)
        XCTAssertEqual(scalar, "ABC123")
    }

    func testOrderDetailDecodes() async throws {
        let server = StubServer()
        let c = L.client(server)
        try server.serve("ujing/orderDetail-unpaid", times: 1)
        let o = try await c.order(L.orderID)
        XCTAssertEqual(o.status, LaundryOrderStatus("10"))
        XCTAssertEqual(o.paid, false)
        XCTAssertTrue(o.isUnpaid)
        XCTAssertEqual(o.price, Money(fen: 400))
        XCTAssertEqual(o.programID, 1)
        XCTAssertEqual(o.countDown, 600)
        XCTAssertEqual(server.requests.first?.queryItem("additional"), "price")
        try server.serve("ujing/orderDetail-washing", times: 1)
        let w = try await c.order(L.orderID)
        XCTAssertTrue(w.status.isWashing)
        XCTAssertEqual(w.remainSeconds, 2400)
        for (name, code) in [("paid", "20"), ("done", "50"), ("failedStart", "52"), ("cancelled", "53")] {
            try server.serve("ujing/orderDetail-\(name)", times: 1)
            let value = try await c.order(L.orderID)
            XCTAssertEqual(value.status.code, code)
        }
    }

    func testOrderDetailExpiredRefusedMalformed() async throws {
        let server = StubServer()
        let c = L.client(server)
        // Captured reply: invalid token → 401 "Token is invalid".
        try server.serve("ujing/orderDetail-badAuth", times: 1)
        await L.expectError(.sessionExpired(.ujing)) { _ = try await c.order("0") }
        try server.serve("ujing/orderDetail-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "30004", message: "订单不存在")) { _ = try await c.order(L.orderID) }
        let ok = try FixtureLoader.load("ujing/orderDetail-unpaid")
        var data = try XCTUnwrap(ok.responseBodyValue?["data"]?.object)
        data["status"] = nil
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        await L.expectError(.malformed(.ujing, "data.status")) { _ = try await c.order(L.orderID) }
        data["status"] = .int(10); data["payPrice"] = .string("3.5")
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        let priced = try await c.order(L.orderID)
        XCTAssertEqual(priced.price, Money(fen: 350))
        data["payPrice"] = .string("free")
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        await L.expectError(.malformed(.ujing, "data.payPrice")) { _ = try await c.order(L.orderID) }
        let before = server.requests.count
        await L.expectError(.badRequest(.ujing)) { _ = try await c.order("../x") }
        XCTAssertEqual(server.requests.count, before)
    }

    // MARK: Payment

    func testPaymentMethods() async throws {
        let server = StubServer()
        let c = L.client(server)
        try server.serve("ujing/paymentMethods-ok", times: 1)
        let channels = try await c.paymentMethods(L.orderID)
        XCTAssertEqual(channels, [PayChannel(channel: "alipayF2F", branchType: 0)])
        XCTAssertEqual(server.requests.last?.queryItem("include"), "alipay")
        try server.serve("ujing/paymentMethods-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "30021", message: "订单状态已变更")) { _ = try await c.paymentMethods(L.orderID) }
        try unauthorized(server, "GET", UjingEndpoints.methods)
        await L.expectError(.sessionExpired(.ujing)) { _ = try await c.paymentMethods(L.orderID) }
        server.respond("GET", L.base + UjingEndpoints.methods, body: L.json(#"{"code":0,"data":{}}"#), times: 1)
        await L.expectError(.malformed(.ujing, "data.channels")) { _ = try await c.paymentMethods(L.orderID) }
    }

    func testPaymentArgumentsQueryAndOutcomes() async throws {
        let server = StubServer()
        let c = L.client(server)
        let f2f = PayChannel(channel: "alipayF2F", branchType: 0)
        try server.serve("ujing/paymentArguments-f2f", times: 1)
        let args = try await c.paymentArguments(L.orderID, channel: f2f)
        XCTAssertNotNil(args.data["url"])
        XCTAssertFalse("\(args)".contains("alipays"))
        let r = try XCTUnwrap(server.requests.last)
        XCTAssertEqual(r.queryItem("channel"), "alipayF2F")
        XCTAssertEqual(r.queryItem("payVersion"), "1")
        XCTAssertEqual(r.queryItem("branchType"), "0")
        XCTAssertEqual(r.queryItem("alipayF2FNoAds"), "true")
        XCTAssertNil(r.queryItem("chooseSign"))

        try server.serve("ujing/paymentArguments-sdk", times: 1)
        _ = try await c.paymentArguments(L.orderID, channel: PayChannel(channel: "alipay"))
        XCTAssertNil(server.requests.last?.queryItem("alipayF2FNoAds"))

        try server.serve("ujing/paymentArguments-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "30022", message: "订单已超时，请重新下单")) { _ = try await c.paymentArguments(L.orderID, channel: f2f) }
        try unauthorized(server, "GET", UjingEndpoints.arguments)
        await L.expectError(.sessionExpired(.ujing)) { _ = try await c.paymentArguments(L.orderID, channel: f2f) }
        server.fail("GET", L.base + UjingEndpoints.arguments, with: .networkConnectionLost, times: 1)
        await L.expectError(.uncertain(.ujing)) { _ = try await c.paymentArguments(L.orderID, channel: f2f) }
        server.respond("GET", L.base + UjingEndpoints.arguments, body: L.json(#"{"code":0,"data":"x"}"#), times: 1)
        await L.expectError(.uncertain(.ujing)) { _ = try await c.paymentArguments(L.orderID, channel: f2f) }
        let before = server.requests.count
        await L.expectError(.badRequest(.ujing)) { _ = try await c.paymentArguments(L.orderID, channel: PayChannel(channel: "alipayWithhold")) }
        XCTAssertEqual(server.requests.count, before)
    }

    func testCancel() async throws {
        let server = StubServer()
        let c = L.client(server)
        try server.serve("ujing/orderCancel-ok", times: 1)
        try await c.cancel(L.orderID)
        XCTAssertEqual(server.requests.last?.bodyField("orderId"), L.orderID)
        try server.serve("ujing/orderCancel-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "30031", message: "订单已支付，无法取消")) { try await c.cancel(L.orderID) }
        try unauthorized(server, "POST", UjingEndpoints.cancel(L.orderID))
        await L.expectError(.sessionExpired(.ujing)) { try await c.cancel(L.orderID) }
        server.fail("POST", L.base + UjingEndpoints.cancel(L.orderID), with: .timedOut, times: 1)
        await L.expectError(.uncertain(.ujing)) { try await c.cancel(L.orderID) }
        server.respond("POST", L.base + UjingEndpoints.cancel(L.orderID), body: L.json("{}"), times: 1)
        await L.expectError(.uncertain(.ujing)) { try await c.cancel(L.orderID) }
    }

    // MARK: Plumbing

    func testNoTokenFailsLocallyAndLogsCarryNoQuery() async throws {
        let server = StubServer()
        await L.expectError(.sessionExpired(.ujing)) { _ = try await L.client(server, token: nil).order(L.orderID) }
        XCTAssertTrue(server.requests.isEmpty)

        let log = RecordingLogSink()
        try server.serve("ujing/orderDetail-unpaid")
        _ = try await L.client(server, log: log).order(L.orderID)
        let line = try XCTUnwrap(log.entries.last?.line)
        XCTAssertFalse(line.contains("additional"))
        XCTAssertFalse(line.contains(L.token))
        XCTAssertTrue(line.contains("code=0"))
    }

    func testBadMobileIDNeverSends() async throws {
        let server = StubServer()
        let c = UjingClient(http: server.makeClient(allowedHosts: AllowedHosts.laundry),
                            device: UjingDevice(mobileID: "not-a-uuid", userAgent: "x"), token: L.token)
        await L.expectError(.badRequest(.ujing)) { _ = try await c.order(L.orderID) }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testEveryUjingFixtureLoads() throws {
        let names = FixtureLoader.allNames().filter { $0.hasPrefix("ujing/") }
        XCTAssertGreaterThanOrEqual(names.count, 30)
        for n in names {
            let f = try FixtureLoader.load(n)
            XCTAssertEqual(f.url.host, "phoenix.ujing.online", n)
        }
    }
}
