import XCTest
@testable import Core
import CoreTestSupport

enum T {
    static let syscustid = "TESTsyscustid0000000000000000000000000001%"
    static let custid = "TESTcustid0000000000000000000000000000001%"
    static let pcUrl = "https://ecykt.gdbtu.edu.cn/ykt-view/authcsatoken?areacode=450010&redirect=%2Fhome&ticket=SYNTHETIC-TICKET-1"
    static func session(token: String = "REDACTED_TOKEN_2", syscustid: String = T.syscustid) -> EcyktSession {
        EcyktSession(token: token, syscustid: syscustid, custid: T.custid, cardUnionID: "TESTid00000000000000000000000001")
    }

    static func expectError(_ expected: ServiceError, file: StaticString = #filePath, line: UInt = #line,
                            _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let e as ServiceError {
            XCTAssertEqual(e, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    /// `getMyECard-ok` with a synthetic pcUrl (the capture's is redacted).
    static func eCardWithTicket() throws -> Fixture {
        let f = try FixtureLoader.load("portal/getMyECard-ok")
        guard case .object(var root)? = f.responseBodyValue, case .object(var data)? = root["data"] else { throw FixtureError.invalid("getMyECard", "shape") }
        data["pcUrl"] = .string(pcUrl)
        root["data"] = .object(data)
        return f.withResponseBody(.object(root))
    }

    /// Synthetic `csalogintoken` answer (never captured; shape from the official JS).
    static func exchangeBody(token: String) -> Data {
        Data(#"{"code":0,"msg":"操作成功","data":{"syscustid":"SYNTH-SYS-NEW","isbind":1,"status":"1","token":"\#(token)"}}"#.utf8)
    }
    static let exchangeURL = "https://ecykt.gdbtu.edu.cn/ykt-mini/verify/csalogintoken/450010"

    /// Replace a fixture's `data` with a modified copy.
    static func editingData(_ f: Fixture, _ edit: (inout JSONValue) -> Void) -> Fixture {
        guard case .object(var root)? = f.responseBodyValue, var data = root["data"] else { return f }
        edit(&data)
        root["data"] = data
        return f.withResponseBody(.object(root))
    }
}

// MARK: - Portal

final class PortalClientTests: XCTestCase {
    func testMyInfoParsesDormAddressAndSendsPortalHeaders() async throws {
        let server = StubServer()
        try server.serve("portal/getMyInfo-ok")
        let r = try await PortalClient(http: server.makeClient()).myInfo(PortalToken("PT"))
        XCTAssertEqual(r.raw, "星湖校区99栋9号1层991房")
        XCTAssertEqual(r.address?.chineseFloorLabel, "一楼")
        let req = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(req.header("X-Id-Token"), "PT")
        XCTAssertEqual(req.header("X-Device-Info"), "PC")
        XCTAssertEqual(req.header("X-Terminal-Info"), "PC")
    }

    func testPortalExpiryShapes() async throws {
        for name in ["portal/getMyInfo-badtoken", "portal/getMyInfo-notoken"] {
            let server = StubServer()
            try server.serve(name)
            await T.expectError(.sessionExpired(.portal)) { _ = try await PortalClient(http: server.makeClient()).myInfo(PortalToken("x")) }
        }
    }

    /// The portal says a dead token with HTTP 200 `code -1001/-1`; a bare 401/403 comes from a
    /// gateway or rate limit and says nothing about the login.
    func testABare401Or403IsARefusalNotExpiry() async throws {
        for status in [401, 403] {
            let server = StubServer()
            server.respond("GET", "https://portal.gdbtu.edu.cn/portalData/v2/personalData/getMyInfo", status: status, body: Data())
            await T.expectError(.rejected(.portal, code: "HTTP \(status)", message: "")) {
                _ = try await PortalClient(http: server.makeClient()).myInfo(PortalToken("x"))
            }
        }
    }

    func testPortalRefusalAndMalformed() async throws {
        let server = StubServer()
        server.respond("GET", "https://portal.gdbtu.edu.cn/portalData/v2/personalData/getMyInfo",
                       body: Data(#"{"code":5,"message":"系统维护中","data":null}"#.utf8), times: 1)
        server.respond("GET", "https://portal.gdbtu.edu.cn/portalData/v2/personalData/getMyInfo",
                       body: Data(#"{"code":0,"message":null,"data":{"szbj":"x"}}"#.utf8))
        let client = PortalClient(http: server.makeClient())
        await T.expectError(.rejected(.portal, code: "5", message: "系统维护中")) { _ = try await client.myInfo(PortalToken("x")) }
        await T.expectError(.malformed(.portal, "data.gydz")) { _ = try await client.myInfo(PortalToken("x")) }
    }

    func testECardTicketURL() async throws {
        let server = StubServer()
        server.serve(try T.eCardWithTicket())
        let url = try await PortalClient(http: server.makeClient()).eCardTicketURL(PortalToken("x"))
        XCTAssertEqual(CASTicket.extract(from: url), "SYNTHETIC-TICKET-1")

        // The capture's redacted placeholder is not a usable URL.
        let redacted = StubServer()
        try redacted.serve("portal/getMyECard-ok")
        await T.expectError(.malformed(.portal, "data.pcUrl")) { _ = try await PortalClient(http: redacted.makeClient()).eCardTicketURL(PortalToken("x")) }
    }
}

// MARK: - ecykt

final class EcyktLivenessTests: XCTestCase {
    func testBoundCardsOK() async throws {
        let server = StubServer()
        try server.serve("ecykt/getSysBindCustInfo-ok")
        let cards = try await EcyktClient(http: server.makeClient()).boundCards(T.session())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].custid, "TESTid00000000000000000000000002")
        XCTAssertEqual(cards[0].unionID, "TESTid00000000000000000000000001")
        XCTAssertEqual(cards[0].areaName, "星湖校区")
    }

    func testBadTokenIsSessionExpired() async throws {
        let server = StubServer()
        try server.serve("ecykt/getSysBindCustInfo-badToken")
        await T.expectError(.sessionExpired(.ecykt)) { _ = try await EcyktClient(http: server.makeClient()).boundCards(T.session(token: "REDACTED_TOKEN_3")) }
    }

    func testMalformedBoundCards() async throws {
        let ok = try FixtureLoader.load("ecykt/getSysBindCustInfo-ok")
        let noCustid = T.editingData(ok) { data in
            if case .array(var rows) = data, case .object(var o) = rows[0] { o["custid"] = nil; rows[0] = .object(o); data = .array(rows) }
        }
        let wrongType = T.editingData(ok) { $0 = .string("[]") }
        for (f, path) in [(noCustid, "data[0].custid"), (wrongType, "data")] {
            let server = StubServer()
            server.serve(f)
            await T.expectError(.malformed(.ecykt, path)) { _ = try await EcyktClient(http: server.makeClient()).boundCards(T.session()) }
        }
        let server = StubServer()
        server.respond("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/api/customer/getSysBindCustInfo", body: Data(#"{"msg":"x"}"#.utf8))
        await T.expectError(.malformed(.ecykt, "code")) { _ = try await EcyktClient(http: server.makeClient()).boundCards(T.session()) }
    }

    func testRequestShape() async throws {
        let server = StubServer()
        try server.serve("ecykt/getSysBindCustInfo-ok")
        _ = try await EcyktClient(http: server.makeClient()).boundCards(T.session())
        let r = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.header("acc_token"), "REDACTED_TOKEN_2")
        XCTAssertEqual(r.bodyField("acc_token"), "REDACTED_TOKEN_2")
        XCTAssertEqual(r.bodyField("syscustid"), T.syscustid)
        XCTAssertEqual(r.bodyField("areacode"), "450010")
        XCTAssertEqual(r.bodyField("version"), "v1.1.55")
        XCTAssertEqual(r.bodyField("appid"), "wx7077a0b57d156efe")
        XCTAssertNil(r.bodyJSON?["timestamp"])
        XCTAssertEqual(r.header("Origin"), "https://ecykt.gdbtu.edu.cn")
        XCTAssertTrue(r.header("Content-Type")?.hasPrefix("application/json") ?? false)
    }
}

final class EcyktFreshLoginTests: XCTestCase {
    func testFreshLoginSuccess() async throws {
        let f = try FixtureLoader.load("ecykt/loginBySysId-mintSeries1")
        let server = StubServer()
        server.serve(f)
        let s = T.session(token: f.requestBody?["acc_token"]?.text ?? "", syscustid: f.requestBody?["syscustid"]?.text ?? "")
        let login = try await EcyktClient(http: server.makeClient()).freshLogin(s)
        XCTAssertEqual(login.isbind, 1)
        XCTAssertEqual(login.token, "REDACTED_TOKEN_9")
        XCTAssertNotEqual(login.syscustid, s.syscustid, "syscustid is re-encrypted per call")
        let r = try XCTUnwrap(server.requests.first)
        XCTAssertNil(r.bodyJSON?["timestamp"])
        XCTAssertEqual(r.bodyField("redirect"), "/recharge?isbind=1")
        XCTAssertEqual(r.bodyField("syscustid"), s.syscustid)
    }

    func testFreshLoginFailures() async throws {
        let cases: [(String, ServiceError)] = [
            ("ecykt/loginBySysId-badToken", .sessionExpired(.ecykt)),
            ("ecykt/loginBySysId-missingSyscustid", .badRequest(.ecykt)),
        ]
        for (name, expected) in cases {
            let server = StubServer()
            try server.serve(name)
            await T.expectError(expected) { _ = try await EcyktClient(http: server.makeClient()).freshLogin(T.session()) }
        }
        let server = StubServer()
        server.respond("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/api/customer/loginBySysId",
                       body: Data(#"{"code":0,"msg":"操作成功","data":{"syscustid":"x","isbind":1}}"#.utf8))
        await T.expectError(.malformed(.ecykt, "data.token")) { _ = try await EcyktClient(http: server.makeClient()).freshLogin(T.session()) }
    }

    func testTicketExchange() async throws {
        let server = StubServer()
        server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "NEW-TOKEN"))
        let login = try await EcyktClient(http: server.makeClient()).exchange(ticket: "SYNTHETIC-TICKET-1")
        XCTAssertEqual(login.token, "NEW-TOKEN")
        XCTAssertEqual(login.syscustid, "SYNTH-SYS-NEW")
        let r = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(r.bodyJSON, .object(["ticket": .string("SYNTHETIC-TICKET-1")]))
        XCTAssertNil(r.header("acc_token"))
    }

    func testSignData() async throws {
        let server = StubServer()
        try server.serve("ecykt/getSignData-ok")
        let h = try await EcyktClient(http: server.makeClient()).signData(T.session(), custid: T.custid)
        XCTAssertEqual(h.userId, "90001")
        XCTAssertEqual(h.deptId, "0099")
        XCTAssertFalse("\(h)".contains("90001"))
        let bad = StubServer()
        try bad.serve("ecykt/getSignData-badToken")
        await T.expectError(.sessionExpired(.ecykt)) { _ = try await EcyktClient(http: bad.makeClient()).signData(T.session(), custid: T.custid) }
    }
}

final class EcyktBalanceTests: XCTestCase {
    func testBalanceOK() async throws {
        let server = StubServer()
        try server.serve("ecykt/getUserBalance-ok")
        let money = try await EcyktClient(http: server.makeClient()).balance(T.session(), custid: T.custid)
        XCTAssertEqual(money, Money(fen: 790))
    }

    func testMissingCustidEmptyBodyIsBadRequestNotExpiry() async throws {
        let server = StubServer()
        try server.serve("ecykt/getUserBalance-missingCustid")
        await T.expectError(.badRequest(.ecykt)) { _ = try await EcyktClient(http: server.makeClient()).balance(T.session(), custid: "") }
    }

    /// Balance does not validate the token: a `-1` here is never read as expiry.
    func testMinusOneFromNonValidatingEndpointIsRejection() async throws {
        let server = StubServer()
        server.respond("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/scanpay/getUserBalance", body: Data(#"{"code":-1,"msg":"登录状态已过期，请重新登录！"}"#.utf8))
        await T.expectError(.rejected(.ecykt, code: "-1", message: "登录状态已过期，请重新登录！")) {
            _ = try await EcyktClient(http: server.makeClient()).balance(T.session(), custid: T.custid)
        }
    }

    func testMalformedAndRefusedBalance() async throws {
        let ok = try FixtureLoader.load("ecykt/getUserBalance-ok")
        let server = StubServer()
        server.serve(T.editingData(ok) { $0 = .string("abc") }, times: 1)
        server.respond("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/scanpay/getUserBalance", body: Data(#"{"code":2,"msg":"卡已挂失"}"#.utf8), times: 1)
        server.respond("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/scanpay/getUserBalance", status: 401, body: Data())
        let c = EcyktClient(http: server.makeClient())
        await T.expectError(.malformed(.ecykt, "data")) { _ = try await c.balance(T.session(), custid: T.custid) }
        await T.expectError(.rejected(.ecykt, code: "2", message: "卡已挂失")) { _ = try await c.balance(T.session(), custid: T.custid) }
        // A bare 401 is a gateway's, not the card system's word on the login (that is HTTP 200 code -1).
        await T.expectError(.rejected(.ecykt, code: "HTTP 401", message: "")) { _ = try await c.balance(T.session(), custid: T.custid) }
    }

    func testCardRecords() async throws {
        let server = StubServer()
        try server.serve("ecykt/card-getRecordList-ok")
        let page = try await EcyktClient(http: server.makeClient()).cardRecords(T.session(), custid: T.custid, begin: "20260930", end: "20261030", pageSize: 5)
        XCTAssertEqual(page.total, 36)
        XCTAssertEqual(page.rows.first?.amount, Money(fen: 13))
        XCTAssertEqual(page.rows.first?.balanceAfter, Money(fen: 1234))
        XCTAssertEqual(page.rows.first?.date, "20260110")
        XCTAssertEqual(page.rows.map(\.voucher), (0..<5).map { "9900000000000000000\($0)" })
        XCTAssertEqual(server.requests.first?.bodyField("pageSize"), "5")
        XCTAssertFalse(page.isComplete(pageSize: 5))
    }

    /// A voucher sent as a number is kept only when it is exact: a long one read as a double
    /// has lost digits (two purchases could share it), so that row has no voucher.
    func testCardRecordVoucherSentAsANumber() async throws {
        let ok = try FixtureLoader.load("ecykt/card-getRecordList-ok")
        let server = StubServer()
        // As JSON sends it: 20 digits do not fit an integer, so they are read as a double.
        let long = try JSONValue.parse("99000000000000000001")
        guard case .double = long else { return XCTFail("\(long)") }
        server.serve(T.editingData(ok) {
            guard case .object(var d) = $0, case .array(var rows)? = d["rows"],
                  case .object(var first) = rows[0], case .object(var second) = rows[1] else { return XCTFail("rows") }
            first["voucherno"] = long
            second["voucherno"] = .int(990000000000000002)
            rows[0] = .object(first); rows[1] = .object(second)
            d["rows"] = .array(rows); $0 = .object(d)
        })
        let page = try await EcyktClient(http: server.makeClient()).cardRecords(T.session(), custid: T.custid, begin: "20260930", end: "20261030", pageSize: 5)
        XCTAssertNil(page.rows[0].voucher)
        XCTAssertEqual(page.rows[1].voucher, "990000000000000002")
        XCTAssertEqual(page.rows[2].voucher, "99000000000000000002")
    }

    /// A reply without a total is complete only when the page was not filled.
    func testCardRecordsWithoutATotal() async throws {
        let ok = try FixtureLoader.load("ecykt/card-getRecordList-ok")
        let server = StubServer()
        server.serve(T.editingData(ok) { if case .object(var d) = $0 { d["total"] = nil; $0 = .object(d) } })
        let page = try await EcyktClient(http: server.makeClient()).cardRecords(T.session(), custid: T.custid, begin: "20260930", end: "20261030", pageSize: 5)
        XCTAssertNil(page.total)
        XCTAssertEqual(page.rows.count, 5)
        XCTAssertFalse(page.isComplete(pageSize: 5), "a full page may have more after it")
        XCTAssertTrue(page.isComplete(pageSize: 6))
    }

    func testRecordPageCompleteness() {
        let row = CardRecord(date: "20261030", time: "120000", title: "x", amount: Money(fen: 1), balanceAfter: nil, direction: "1")
        XCTAssertTrue(CardRecordPage(total: 2, rows: [row, row]).isComplete(pageSize: 2))
        XCTAssertFalse(CardRecordPage(total: 3, rows: [row, row]).isComplete(pageSize: 2))
        XCTAssertTrue(CardRecordPage(total: nil, rows: [row]).isComplete(pageSize: 2))
        XCTAssertTrue(CardRecordPage(total: nil, rows: []).isComplete(pageSize: 2))
        XCTAssertFalse(CardRecordPage(total: nil, rows: [row, row]).isComplete(pageSize: 2))
    }
}

final class EcyktElectricityTests: XCTestCase {
    func server(_ names: [String]) throws -> StubServer {
        let s = StubServer()
        for n in names { try s.serve(n, matchBody: ["server", "buildingID"]) }
        return s
    }

    func testDirectoryLevels() async throws {
        let s = try server(["ecykt/electric-getBuildingInfo-root", "ecykt/electric-getBuildingInfo-level1", "ecykt/electric-getBuildingInfo-level2",
                            "ecykt/electric-getBuildingInfo-level3", "ecykt/electric-getBuildingInfo-level4", "ecykt/electric-getBuildingInfo-leafEmpty"])
        let c = EcyktClient(http: s.makeClient())
        let root = try await c.buildings(T.session(), parent: nil)
        XCTAssertEqual(root.first, PowerNode(id: "991001", name: "星湖校区"))
        XCTAssertEqual(root.count, 4)
        let l1 = try await c.buildings(T.session(), parent: "991001")
        XCTAssertEqual(l1.first?.name, "半山公寓")
        let l2 = try await c.buildings(T.session(), parent: "991001001")
        XCTAssertEqual(l2.map(\.name), ["1栋", "2栋", "99栋"])
        let l3 = try await c.buildings(T.session(), parent: "991001001000109")
        XCTAssertEqual(l3.map(\.name), ["1楼", "2楼", "3楼"])
        let l4 = try await c.buildings(T.session(), parent: "991001001000109000001")
        XCTAssertEqual(l4.map(\.name), ["989", "990", "991"])
        let leaf = try await c.buildings(T.session(), parent: "991001001000109000001003")
        XCTAssertEqual(leaf, [])
        XCTAssertTrue(s.unmatched.isEmpty)
        let r = try XCTUnwrap(s.requests.first)
        XCTAssertEqual(r.bodyField("server"), "/api/getBuildingInfo")
        XCTAssertNil(r.bodyJSON?["buildingID"])
        XCTAssertNil(r.bodyJSON?["timestamp"])
        XCTAssertTrue(r.header("Referer")?.contains("powernew_450010") ?? false)
    }

    func testMeterRowsParseStrictly() async throws {
        let s = try server(["ecykt/electric-getMeterStatus-ok", "ecykt/electric-getMeterStatus-room", "ecykt/electric-getMeterStatus-leaf",
                            "ecykt/electric-getMeterStatus-unknownBuilding"])
        let c = EcyktClient(http: s.makeClient())
        let campus = try await c.meters(T.session(), nodeID: "991001")
        XCTAssertEqual(campus.count, 12)
        XCTAssertEqual(campus[0].name, "8栋101")
        XCTAssertEqual(campus[0].leftMoney, Money(fen: 5000))
        XCTAssertEqual(campus[0].online, true)
        let room = try await c.meters(T.session(), nodeID: "991001001000109000001003")
        XCTAssertEqual(room, [Meter(comAddress: "000000000991", name: "99栋991", leftMoney: Money(fen: 3692),
                                    remainingKWh: DecimalText.parse("52.00"), dailyUseKWh: DecimalText.parse("3.2"),
                                    price: DecimalText.parse("0.7100"), online: true, switchState: "合闸-", updatedAt: "2026-10-30 08:10:22")])
        let floor = try await c.meters(T.session(), nodeID: "991001001000109000001")
        XCTAssertEqual(floor.count, 3)
        let unknown = try await c.meters(T.session(), nodeID: "999999")
        XCTAssertEqual(unknown, [], "[] is success: 没找到电表")
    }

    func testMissingServerIsBadRequestAndMalformedRows() async throws {
        let s = try server(["ecykt/electric-service-missingServer"])
        // The client always sends `server`; replay the 500 shape on a normal call.
        let f = try FixtureLoader.load("ecykt/electric-service-missingServer")
        s.respond("POST", f.url.absoluteString, body: f.responseBody)
        await T.expectError(.badRequest(.ecykt)) { _ = try await EcyktClient(http: s.makeClient()).meters(T.session(), nodeID: "1") }

        let room = try FixtureLoader.load("ecykt/electric-getMeterStatus-room")
        let cases: [(JSONValue, String)] = [
            (.string(#"[{"piplineName":"99栋991"}]"#), "data[0].comAddress"),
            (.string("not json"), "data<json>"),
            (.int(3), "data"),
        ]
        for (data, path) in cases {
            let s2 = StubServer()
            s2.serve(T.editingData(room) { $0 = data })
            await T.expectError(.malformed(.ecykt, path)) { _ = try await EcyktClient(http: s2.makeClient()).meters(T.session(), nodeID: "1") }
        }
    }

    /// The recharge WebView's electricity entry: the query as captured, ciphertext `%` encoded as `%25`.
    func testPowerEntryURLMatchesTheCapture() throws {
        let fixtureURL = try FixtureLoader.load("ecykt/getPowerUrl-ok").url
        let url = EcyktClient.powerEntryURL(T.session(), custid: T.custid)
        XCTAssertEqual(url.path, fixtureURL.path)
        XCTAssertEqual(url.query, fixtureURL.query)
    }
}
