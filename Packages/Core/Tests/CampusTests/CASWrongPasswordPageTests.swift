import XCTest
@testable import Core
import CoreTestSupport

/// A refused password, however the school's page says it: an HTTP 401 re-rendered login page,
/// the error in the page's markup instead of `var errors`, or wording that also mentions a lock
/// still to come. Only a lock, captcha or check already in force (or a page we don't know) is not
/// a wrong password, and then the failure says which (`SchoolLoginBlock`).
final class CASWrongPasswordPageTests: XCTestCase {
    /// The login page as Apereo CAS re-renders it after a refused password, error in its markup.
    static func refusedPage(_ errorMarkup: String) -> Data {
        var html = "<html><head><style>.errors{color:red}</style></head><body>"
        html += "<form id=\"fm1\" action=\"login\" method=\"post\">" + errorMarkup
        html += "<input name=\"username\" value=\"99100991\"/><input type=\"password\" name=\"password\"/>"
        html += "<input type=\"hidden\" name=\"execution\" value=\"\(CASFake.execution)\"/></form>"
        html += "<script>var isMobile = false;</script></body></html>"
        return Data(html.utf8)
    }

    func post(status: Int, body: Data) async throws -> SchoolLoginFailure? {
        let server = StubServer()
        let (_, pem) = try CASFake.keyPair()
        CASFake.serveForm(server, pem: pem)
        server.respond("POST", CASFake.loginURL, status: status, headers: ["Content-Type": "text/html"], body: body)
        do { _ = try await CASLoginClient(http: server.makeClient()).login(account: "99100991", password: "synthetic-pw-991", visitorID: CASFake.visitor); return nil }
        catch { return error as? SchoolLoginFailure }
    }

    func testA401PageThatSaysThePasswordIsWrongIsAWrongPassword() async throws {
        let markup = #"<div id="msg" class="errors"><h2>认证失败</h2><p>用户名或者密码错误</p></div>"#
        let failure = try await post(status: 401, body: Self.refusedPage(markup))
        XCTAssertEqual(failure, .wrongCredentials)
        let scripted = try await post(status: 401, body: CASFake.page(errors: #"["账号或密码错误"]"#))
        XCTAssertEqual(scripted, .wrongCredentials)
    }

    func testA401PageWithoutAKnownErrorStillGoesToTheWebPage() async throws {
        let empty = try await post(status: 401, body: CASFake.page())
        XCTAssertEqual(empty, .cannotLoginDirectly(.unknown))
        let unknown = try await post(status: 401, body: Self.refusedPage(#"<div class="alert alert-danger">出了点问题</div>"#))
        XCTAssertEqual(unknown, .cannotLoginDirectly(.unknown))
        let forbidden = try await post(status: 403, body: Self.refusedPage(#"<div id="msg" class="errors">密码错误</div>"#))
        XCTAssertEqual(forbidden, .cannotLoginDirectly(.unknown), "only 200 and 401 are the login page answering")
    }

    func testAWrongPasswordInTheMarkupOfA200PageIsAWrongPassword() async throws {
        let failure = try await post(status: 200, body: Self.refusedPage(#"<div class="alert alert-danger" role="alert"><span>账号或者密码错误</span></div>"#))
        XCTAssertEqual(failure, .wrongCredentials)
    }

    func testErrorsAreReadFromTheUsualCASMarkup() {
        func errors(_ markup: String) -> [String]? { CASPage.errors(in: Self.refusedPage(markup)) }
        XCTAssertEqual(errors(#"<div id="msg" class="errors"><h2>Authentication failure</h2><p>Invalid credentials.</p></div>"#),
                       ["Authentication failure Invalid credentials."])
        XCTAssertEqual(errors(#"<span id="password.errors" class="errors">密码错误</span>"#), ["密码错误"])
        XCTAssertEqual(errors(#"<span id="username.errors">用户不存在</span>"#), ["用户不存在"])
        XCTAssertEqual(errors(#"<div class="alert alert-danger" role="alert"><div><span>账号或者密码错误</span></div></div>"#), ["账号或者密码错误"])
        XCTAssertEqual(errors(#"<p id="errormsg">用户名或密码错误</p>"#), ["用户名或密码错误"])
        XCTAssertEqual(errors(#"<div class="errors"><script>var e = "x";</script>密码&nbsp;错误&amp;</div>"#), ["密码 错误&"])
        XCTAssertNil(errors(#"<div class="alert alert-danger" style="display:none"></div>"#), "an empty banner is no error")
        XCTAssertNil(errors(#"<div class="error-free">欢迎</div>"#))
        XCTAssertEqual(CASPage.errors(in: CASFake.page(errors: #"["请输入验证码"]"#)), ["请输入验证码"], "the script list is still read")
    }

    func testWrongPasswordWordingWinsOverALockStillToCome() {
        for text in ["密码错误，再错3次账号将被锁定", "用户名或密码错误，也可以用手机短信登录", "账号或密码错误，剩余2次机会，超过将冻结"] {
            XCTAssertEqual(CASPage.classify(errors: [text]), .wrongCredentials, text)
        }
    }

    func testALockCaptchaOrCheckInForceIsNotAWrongPassword() {
        let cases: [(String, SchoolLoginBlock)] = [
            ("账号已锁定", .locked), ("请输入验证码", .captcha), ("账号或密码错误次数过多，账号已锁定", .locked),
            ("登录失败，请输入验证码", .captcha), ("登录失败，账号已冻结", .locked), ("认证失败，请使用手机验证", .mfa),
            ("需要安全验证", .mfa), ("登录过于频繁", .unknown),
        ]
        for (text, block) in cases {
            XCTAssertEqual(CASPage.classify(errors: [text]), .cannotLoginDirectly(block), text)
        }
    }

    func testMoreWaysOfSayingThePasswordIsWrong() {
        for text in ["用户名或者密码错误", "账号或者密码不正确", "认证失败", "登录失败", "Invalid credentials.", "Bad credentials"] {
            XCTAssertEqual(CASPage.classify(errors: [text]), .wrongCredentials, text)
        }
        XCTAssertEqual(CASPage.classify(errors: ["系统维护中"]), .cannotLoginDirectly(.unknown))
        XCTAssertEqual(CASPage.classify(errors: []), .cannotLoginDirectly(.unknown))
    }
}
