import XCTest
import Security
@testable import Core
import CoreTestSupport

/// Synthetic CAS pages and a test-only RSA key; no real school server is ever called.
enum CASFake {
    static let loginURL = SchoolEndpoints.casLoginURL.absoluteString
    static let keyURL = "https://cas.gdbtu.edu.cn/cas/jwt/publicKey"
    static let execution = "e99s991-synthetic-execution"
    static let visitor = "99000000000000000000000000000991"

    static func page(execution: String? = CASFake.execution, errors: String? = nil) -> Data {
        var html = "<html><body><form id=\"fm1\" action=\"login\" method=\"post\">"
        html += "<input name=\"username\"/><input type=\"password\" name=\"password\"/>"
        if let execution { html += "<input type=\"hidden\" name=\"execution\" value=\"\(execution)\"/>" }
        html += "</form><script>var isMobile = false;"
        if let errors { html += "var errors = \(errors);" }
        html += "</script></body></html>"
        return Data(html.utf8)
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func jwt(_ claims: String) -> String {
        base64url(Data("{\"alg\":\"none\"}".utf8)) + "." + base64url(Data(claims.utf8)) + ".c2ln"
    }
    static let idTokenExp = 4_102_444_800
    static var idToken: String { jwt("{\"sub\":\"99100991\",\"exp\":\(idTokenExp)}") }
    static var ticket: String { jwt("{\"sub\":\"99100991\",\"exp\":4102444000,\"idToken\":\"\(idToken)\"}") }

    /// A fresh 2048-bit key pair; the public half as the page serves it (PEM SPKI).
    static func keyPair() throws -> (SecKey, Data) {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let pub = SecKeyCopyPublicKey(priv),
              let pkcs1 = SecKeyCopyExternalRepresentation(pub, nil) as Data? else { throw XCTSkip("no RSA key") }
        let algorithm = der(0x30, Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]))
        let spki = der(0x30, algorithm + der(0x03, Data([0x00]) + pkcs1))
        let pem = "-----BEGIN PUBLIC KEY-----\n" + spki.base64EncodedString(options: .lineLength64Characters) + "\n-----END PUBLIC KEY-----\n"
        return (priv, Data(pem.utf8))
    }

    static func der(_ tag: UInt8, _ content: Data) -> Data {
        let n = content.count
        let length: [UInt8] = n < 0x80 ? [UInt8(n)] : n < 0x100 ? [0x81, UInt8(n)] : [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
        return Data([tag] + length) + content
    }

    static func decrypt(_ field: String, with key: SecKey) -> String? {
        guard field.hasPrefix("__RSA__"), let sealed = Data(base64Encoded: String(field.dropFirst(7))),
              let plain = SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, sealed as CFData, nil) as Data? else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    /// Serves the login page (with a session cookie) and the public key.
    static func serveForm(_ server: StubServer, page: Data = CASFake.page(), pem: Data) {
        server.respond("GET", loginURL, headers: ["Content-Type": "text/html", "Set-Cookie": "SESSION=s991; Path=/cas; Secure; HttpOnly"],
                       body: page, times: 1)
        server.respond("GET", keyURL, headers: ["Content-Type": "text/plain"], body: pem)
    }
}

final class CASLoginClientTests: XCTestCase {
    let server = StubServer()
    var client: CASLoginClient { CASLoginClient(http: server.makeClient(), now: { Date(timeIntervalSince1970: 1_800_000_000) }) }

    func login() async -> Result<PortalToken, Error> {
        do { return .success(try await client.login(account: "99100991", password: "synthetic-pw-991", visitorID: CASFake.visitor)) }
        catch { return .failure(error) }
    }

    func failure(_ r: Result<PortalToken, Error>) -> SchoolLoginFailure? {
        if case .failure(let e) = r { return e as? SchoolLoginFailure }
        return nil
    }

    func testSuccessPostsTheEncryptedFormAndReadsTheIdTokenFromTheTicket() async throws {
        let (priv, pem) = try CASFake.keyPair()
        CASFake.serveForm(server, pem: pem)
        let location = "https://portal.gdbtu.edu.cn/?path=https%3A%2F%2Fportal.gdbtu.edu.cn%2Fmain.html&ticket=" + CASFake.ticket
        server.respond("POST", CASFake.loginURL, status: 302, headers: ["Location": location], body: Data())

        let token = try await login().get()
        XCTAssertEqual(token.value, CASFake.idToken)
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: TimeInterval(CASFake.idTokenExp)))
        XCTAssertTrue(server.unmatched.isEmpty)

        let post = try XCTUnwrap(server.requests.first { $0.method == "POST" })
        let form = post.formFields
        XCTAssertEqual(form["username"], "99100991")
        XCTAssertEqual(CASFake.decrypt(form["password"] ?? "", with: priv), "synthetic-pw-991")
        XCTAssertEqual(form["execution"], CASFake.execution)
        XCTAssertEqual(form["fpVisitorId"], CASFake.visitor)
        XCTAssertEqual(form["failN"], "0")
        XCTAssertEqual(form["_eventId"], "submit")
        XCTAssertTrue(String(decoding: post.body, as: UTF8.self).contains("captcha=&"), "empty captcha is sent")
        XCTAssertNil(form["rememberMe"])
        XCTAssertEqual(post.queryItem("service"), SchoolEndpoints.casService)
        XCTAssertEqual(post.header("Cookie"), "SESSION=s991", "the session from the form page goes with the login")
        XCTAssertEqual(server.requests.map(\.method), ["GET", "GET", "POST"], "one attempt, the redirect is not followed")
        XCTAssertFalse(String(decoding: post.body, as: UTF8.self).contains("synthetic-pw-991"))
    }

    func testWrongPasswordIsReportedOnce() async throws {
        let (_, pem) = try CASFake.keyPair()
        CASFake.serveForm(server, pem: pem)
        server.respond("POST", CASFake.loginURL, headers: ["Content-Type": "text/html"],
                       body: CASFake.page(errors: #"["账号或密码错误"]"#))
        let result = await login()
        XCTAssertEqual(failure(result), .wrongCredentials)
        XCTAssertEqual(server.requests(path: "/cas/login").filter { $0.method == "POST" }.count, 1)
    }

    func testCaptchaLockAndVerificationSendPeopleToTheWebPage() async throws {
        for errors in [#"["请输入验证码"]"#, #"["账号或密码错误次数过多，账号已锁定"]"#, #"[{"message":"需要安全验证"}]"#,
                       #"["出了点问题"]"#, "[]"] {
            let s = StubServer()
            let (_, pem) = try CASFake.keyPair()
            CASFake.serveForm(s, pem: pem)
            s.respond("POST", CASFake.loginURL, headers: ["Content-Type": "text/html"], body: CASFake.page(errors: errors))
            do { _ = try await CASLoginClient(http: s.makeClient()).login(account: "99100991", password: "x", visitorID: CASFake.visitor); XCTFail(errors) }
            catch { XCTAssertEqual(error as? SchoolLoginFailure, .cannotLoginDirectly, errors) }
        }
    }

    func testPageWithoutErrorsIsNotGuessedAsWrongPassword() async throws {
        let (_, pem) = try CASFake.keyPair()
        CASFake.serveForm(server, pem: pem)
        server.respond("POST", CASFake.loginURL, headers: ["Content-Type": "text/html"], body: CASFake.page())
        let result = await login()
        XCTAssertEqual(failure(result), .cannotLoginDirectly)
    }

    func testMissingExecutionStopsBeforeSendingThePassword() async throws {
        let (_, pem) = try CASFake.keyPair()
        CASFake.serveForm(server, page: CASFake.page(execution: nil), pem: pem)
        let result = await login()
        XCTAssertEqual(failure(result), .cannotLoginDirectly)
        XCTAssertTrue(server.requests.allSatisfy { $0.method == "GET" })
    }

    func testUnreadableKeyOrTicketCannotLoginDirectly() async throws {
        CASFake.serveForm(server, pem: Data("-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----".utf8))
        let result = await login()
        XCTAssertEqual(failure(result), .cannotLoginDirectly)
        XCTAssertTrue(server.requests.allSatisfy { $0.method == "GET" })

        let other = StubServer()
        let (_, pem) = try CASFake.keyPair()
        CASFake.serveForm(other, pem: pem)
        other.respond("POST", CASFake.loginURL, status: 302, headers: ["Location": "https://portal.gdbtu.edu.cn/?ticket=not-a-jwt"], body: Data())
        do { _ = try await CASLoginClient(http: other.makeClient()).login(account: "a", password: "b", visitorID: CASFake.visitor); XCTFail() }
        catch { XCTAssertEqual(error as? SchoolLoginFailure, .cannotLoginDirectly) }
    }

    func testNoNetworkIsOffline() async {
        server.fail("GET", CASFake.loginURL, with: .notConnectedToInternet)
        let result = await login()
        XCTAssertEqual(failure(result), .offline)
    }

    /// Once the password is posted, a lost answer is not "offline": the school may have counted it.
    func testNoAnswerToThePostIsReportedAsSuch() async throws {
        let (_, pem) = try CASFake.keyPair()
        for code in [URLError.Code.timedOut, .networkConnectionLost, .notConnectedToInternet] {
            let server = StubServer()
            CASFake.serveForm(server, pem: pem)
            server.fail("POST", CASFake.loginURL, with: code)
            do { _ = try await CASLoginClient(http: server.makeClient()).login(account: "a", password: "b", visitorID: CASFake.visitor); XCTFail() }
            catch { XCTAssertEqual(error as? SchoolLoginFailure, .noAnswer, "\(code)") }
            XCTAssertEqual(server.requests(path: "/cas/login").filter { $0.method == "POST" }.count, 1)
        }
    }

    func testTicketClaimsAndErrorParsing() {
        XCTAssertEqual(CASTicketClaims.portalToken(fromTicket: CASFake.ticket)?.value, CASFake.idToken)
        XCTAssertNil(CASTicketClaims.portalToken(fromTicket: CASFake.jwt("{\"sub\":\"99\"}")))
        XCTAssertEqual(CASPage.errors(in: Data(#"<script>var errors = ["a \"b\" ]", {"m":"c"}];</script>"#.utf8)), ["a \"b\" ]", "c"])
        XCTAssertNil(CASPage.errors(in: Data("<html></html>".utf8)))
        XCTAssertEqual(PortalToken("t", expiresAt: nil).description, "PortalToken(<redacted>)")
    }
}
