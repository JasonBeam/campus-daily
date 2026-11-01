import XCTest
@testable import Core
import CoreTestSupport

final class FixtureLoaderTests: XCTestCase {
    /// Batch 0 acceptance: the loader parses every fixture.
    func testLoaderParsesEveryFixture() throws {
        let names = FixtureLoader.allNames()
        XCTAssertGreaterThan(names.count, 50)
        for name in names {
            if name.contains("localStorage-") { XCTAssertNotNil(try FixtureLoader.loadRaw(name)["value"], name); continue }
            let f = try FixtureLoader.load(name)
            XCTAssertTrue(["GET", "POST"].contains(f.method), name)
            XCTAssertEqual(f.url.scheme, "https", name)
        }
    }

    /// The public repo must not carry captures that show a bad token still returning data.
    func testNoSuccessShapedBadTokenFixtures() throws {
        for name in FixtureLoader.allNames() where name.lowercased().contains("badtoken") {
            let code = try FixtureLoader.load(name).responseBodyValue?["code"]?.text
            XCTAssertNotEqual(code, "0", "\(name) shows data served for a bad token; keep it in private/")
        }
    }

    /// Faked user room is consistent across services.
    func testFakedDormIsConsistent() throws {
        let gydz = try FixtureLoader.load("portal/getMyInfo-ok").responseBodyValue?["data"]?["gydz"]?.text
        XCTAssertEqual(gydz, "星湖校区99栋9号1层991房")
        let rooms = try FixtureLoader.load("ecykt/electric-getBuildingInfo-level4").responseBodyValue?["data"]?.text ?? ""
        XCTAssertTrue(rooms.contains("\"991\""))
        let meter = try FixtureLoader.load("ecykt/electric-getMeterStatus-room").responseBodyValue?["data"]?.text ?? ""
        XCTAssertTrue(meter.contains("99栋991"))
    }
}

final class RedactorTests: XCTestCase {
    func testMasksSecretKeysRecursivelyAndInsideJSONStrings() throws {
        let body: JSONValue = .object([
            "acc_token": .string("T0KEN"), "syscustid": .string("SYS"), "custid": .string("CUST"),
            "ticket": .string("TICKET"), "sign": .string("SIGN"), "sid": .string("SID"), "areacode": .string("450010"),
            "data": .string(#"{"token":"INNER","name":"ok"}"#),
            "list": .array([.object(["logintoken": .string("LT")])]),
        ])
        let text = String(decoding: try Redactor.redact(body).encoded(), as: UTF8.self)
        for secret in ["T0KEN", "SYS", "CUST", "TICKET", "SIGN", "SID", "INNER", "LT"] {
            XCTAssertFalse(text.contains(secret), secret)
        }
        XCTAssertTrue(text.contains("450010"))
        XCTAssertEqual(Redactor.redactHeaders(["acc_token": "x", "X-Id-Token": "y", "Accept": "a"]),
                       ["acc_token": Redactor.mask, "X-Id-Token": Redactor.mask, "Accept": "a"])
        XCTAssertEqual(Redactor.redactURL(URL(string: "https://ecykt.gdbtu.edu.cn/a?ticket=T&custid=C")!), "https://ecykt.gdbtu.edu.cn/a")
        XCTAssertEqual(Redactor.redactBody(Data()), "<empty>")
    }

    /// A card record's voucher number is kept out of logs like the other ids.
    func testMasksACardRecordVoucher() throws {
        let body: JSONValue = .object(["rows": .array([.object(["voucherno": .string("99000000000000000001"), "amount": .string("1.30")])])])
        let text = String(decoding: try Redactor.redact(body).encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("99000000000000000001"), text)
        XCTAssertTrue(text.contains("1.30"))
        XCTAssertTrue(Redactor.isSecret("voucherNo"))
    }
}

final class URLSessionHTTPClientTests: XCTestCase {
    func testLogsCarryNoTokensQueriesOrBodies() async throws {
        let server = StubServer()
        try server.serve("ecykt/getUserBalance-ok")
        let log = RecordingLogSink()
        let client = server.makeClient(log: log)
        let url = URL(string: "https://ecykt.gdbtu.edu.cn/ykt-mini/scanpay/getUserBalance?ticket=SECRET-TICKET")!
        let req = HTTPRequest.postJSON(service: .ecykt, url: url, headers: ["acc_token": "SECRET-TOKEN"],
                                       json: ["acc_token": .string("SECRET-TOKEN"), "custid": .string("SECRET-CUST")])
        let res = try await client.send(req)
        XCTAssertEqual(res.status, 200)
        let line = try XCTUnwrap(log.entries.first).line
        XCTAssertEqual(line.contains("SECRET"), false, line)
        XCTAssertTrue(line.contains("/ykt-mini/scanpay/getUserBalance"))
        XCTAssertTrue(line.contains("code=0"))
        XCTAssertTrue(server.unmatched.isEmpty)
    }

    /// Batch 0 acceptance: `getPowerUrl-ok` 302 is not followed.
    func testRedirectIsReturnedNotFollowed() async throws {
        let server = StubServer()
        let fixture = try FixtureLoader.load("ecykt/getPowerUrl-ok")
        server.serve(fixture)
        let client = server.makeClient()
        let res = try await client.send(HTTPRequest(service: .ecykt, method: .get, url: fixture.url))
        XCTAssertEqual(res.status, 302)
        XCTAssertEqual(res.header("location"), "https://ecykt.gdbtu.edu.cn/ykt-view/powersel?interfaceName=powernew_450010&isbind=1")
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertFalse(server.requests.contains { $0.url.path.contains("powersel") })
    }

    func testHostAllowListAndHTTPSOnly() async throws {
        let server = StubServer()
        let client = server.makeClient(allowedHosts: AllowedHosts.school)
        for url in ["https://example.com/x", "http://ecykt.gdbtu.edu.cn/x", "https://isv.lxt6.cn/x"] {
            do {
                _ = try await client.send(HTTPRequest(service: .ecykt, method: .get, url: URL(string: url)!))
                XCTFail(url)
            } catch let e as ServiceError {
                XCTAssertEqual(e, .badRequest(.ecykt))
            }
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testTransportErrorTaxonomy() async throws {
        let cases: [(URLError.Code, ServiceError)] = [
            (.notConnectedToInternet, .offline), (.networkConnectionLost, .offline), (.cannotFindHost, .offline),
            (.timedOut, .timedOut), (.secureConnectionFailed, .tls), (.serverCertificateUntrusted, .tls),
        ]
        for (code, expected) in cases {
            let server = StubServer()
            server.fail("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/x", with: code)
            let client = server.makeClient()
            let url = URL(string: "https://ecykt.gdbtu.edu.cn/ykt-mini/x")!
            do {
                _ = try await client.send(.postJSON(service: .ecykt, url: url, json: [:]))
                XCTFail("\(code)")
            } catch let e as ServiceError {
                XCTAssertEqual(e, expected, "\(code)")
            }
            // Same failure on a state-changing request is `uncertain`, never offline/timedOut.
            do {
                _ = try await client.send(.postJSON(service: .lxt6, url: url, json: [:], isStateChanging: true))
                XCTFail("\(code)")
            } catch let e as ServiceError {
                XCTAssertEqual(e, .uncertain(.lxt6), "\(code)")
            }
        }
    }

    func testBodyCap() async throws {
        let server = StubServer()
        server.respond("POST", "https://ecykt.gdbtu.edu.cn/ykt-mini/big", body: Data(repeating: 0x20, count: HTTPRequest.defaultBodyLimit + 1))
        let client = server.makeClient()
        let url = URL(string: "https://ecykt.gdbtu.edu.cn/ykt-mini/big")!
        do {
            _ = try await client.send(.postJSON(service: .ecykt, url: url, json: [:]))
            XCTFail()
        } catch let e as ServiceError {
            XCTAssertEqual(e, .malformed(.ecykt, "body"))
        }
        let ok = try await client.send(.postJSON(service: .ecykt, url: url, json: [:], bodyLimit: HTTPRequest.largeBodyLimit))
        XCTAssertEqual(ok.body.count, HTTPRequest.defaultBodyLimit + 1)
    }

    /// No request waits longer than the client's own: a shorter wait asked for is kept, a
    /// longer one is cut to it.
    func testNoRequestWaitsLongerThanTheClient() async throws {
        let server = StubServer()
        let url = URL(string: "https://ecykt.gdbtu.edu.cn/ykt-mini/slow")!
        server.respond("POST", url.absoluteString, body: Data("{}".utf8))
        let client = server.makeClient()
        for asked in [45, 300, 5, nil] as [TimeInterval?] {
            var request = HTTPRequest.postJSON(service: .ecykt, url: url, json: [:])
            request.timeout = asked
            _ = try await client.send(request)
        }
        let own = URLSessionHTTPClient.requestTimeout
        XCTAssertEqual(server.requests.map(\.timeout), [own, own, 5, own])
    }

    func testResponseDecodingStatusesAndJSONInString() throws {
        XCTAssertThrowsError(try ResponseDecoding.json(HTTPResponse(status: 401), service: .ujing)) {
            XCTAssertEqual($0 as? ServiceError, .sessionExpired(.ujing))
        }
        XCTAssertThrowsError(try ResponseDecoding.json(HTTPResponse(status: 403), service: .portal)) {
            XCTAssertEqual($0 as? ServiceError, .sessionExpired(.portal))
        }
        XCTAssertThrowsError(try ResponseDecoding.json(HTTPResponse(status: 200, body: Data("<html>".utf8)), service: .ecykt)) {
            XCTAssertEqual($0 as? ServiceError, .malformed(.ecykt, "$"))
        }
        XCTAssertNil(try ResponseDecoding.json(HTTPResponse(status: 200, body: Data(" \n".utf8)), service: .ecykt))
        let f = try FixtureLoader.load("lxt6/getUserMsg-badSign")
        let root = try XCTUnwrap(try ResponseDecoding.json(HTTPResponse(status: f.status, body: f.responseBody), service: .lxt6))
        XCTAssertEqual(ResponseDecoding.code(root), "-301")
        let ujing = try FixtureLoader.load("ujing/orderDetail-badAuth")
        XCTAssertThrowsError(try ResponseDecoding.json(HTTPResponse(status: ujing.status, body: ujing.responseBody), service: .ujing)) {
            XCTAssertEqual($0 as? ServiceError, .sessionExpired(.ujing))
        }
    }
}
