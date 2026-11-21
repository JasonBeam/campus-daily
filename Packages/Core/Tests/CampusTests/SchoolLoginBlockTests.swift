//
//  SchoolLoginBlockTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/17.
//

import XCTest
@testable import Core
import CoreTestSupport

/// A login the school did not call wrong says what was in the way, read from the page it sent
/// back (synthetic pages, no school server): a lock, a captcha, an extra check, a password
/// change or activation, or a page we don't recognise. A wrong password and no answer stay as
/// they were.
final class SchoolLoginBlockTests: XCTestCase {
    func post(status: Int, body: Data, headers: [String: String] = ["Content-Type": "text/html"]) async throws -> SchoolLoginFailure? {
        let server = StubServer()
        let (_, pem) = try CASFake.keyPair()
        CASFake.serveForm(server, pem: pem)
        server.respond("POST", CASFake.loginURL, status: status, headers: headers, body: body)
        do {
            _ = try await CASLoginClient(http: server.makeClient()).login(account: "99100991", password: "synthetic-pw-991",
                                                                          visitorID: CASFake.visitor)
            return nil
        } catch { return error as? SchoolLoginFailure }
    }

    func testALockedAccountIsLocked() async throws {
        for errors in [#"["账号已锁定，请 5 分钟后再试"]"#, #"["密码错误次数过多，账号已被锁定"]"#, #"["账号已冻结"]"#,
                       #"["Your account is locked."]"#, #"["登录失败次数过多"]"#] {
            let failure = try await post(status: 401, body: CASFake.page(errors: errors))
            XCTAssertEqual(failure, .cannotLoginDirectly(.locked), errors)
        }
        let markup = CASWrongPasswordPageTests.refusedPage(#"<div id="msg" class="errors"><p>账号已锁定</p></div>"#)
        let fromMarkup = try await post(status: 200, body: markup)
        XCTAssertEqual(fromMarkup, .cannotLoginDirectly(.locked))
    }

    func testACaptchaIsACaptcha() async throws {
        for errors in [#"["请输入验证码"]"#, #"["验证码错误"]"#, #"["Captcha required"]"#] {
            let failure = try await post(status: 200, body: CASFake.page(errors: errors))
            XCTAssertEqual(failure, .cannotLoginDirectly(.captcha), errors)
        }
    }

    func testAnExtraCheckIsMFA() async throws {
        for errors in [#"["需要二次认证"]"#, #"["新设备登录，需要安全验证"]"#, #"["请输入短信验证码"]"#, #"["请使用手机验证"]"#,
                       #"["请输入邮箱收到的验证码"]"#, #"[{"message":"MFA required"}]"#] {
            let failure = try await post(status: 200, body: CASFake.page(errors: errors))
            XCTAssertEqual(failure, .cannotLoginDirectly(.mfa), errors)
        }
    }

    func testAPasswordChangeOrActivationIsAPasswordChange() async throws {
        for errors in [#"["密码已过期，请修改密码"]"#, #"["当前密码为弱密码，请修改密码后登录"]"#, #"["首次登录请先激活账号"]"#,
                       #"["初始密码不能登录，请重置密码"]"#] {
            let failure = try await post(status: 401, body: CASFake.page(errors: errors))
            XCTAssertEqual(failure, .cannotLoginDirectly(.passwordChange), errors)
        }
    }

    func testAPageWeDontKnowIsUnknown() async throws {
        for body in [CASFake.page(), CASFake.page(errors: #"["系统维护中"]"#), CASFake.page(errors: #"["登录过于频繁"]"#),
                     CASFake.page(errors: #"["账号异常"]"#)] {
            let failure = try await post(status: 200, body: body)
            XCTAssertEqual(failure, .cannotLoginDirectly(.unknown))
        }
        let forbidden = try await post(status: 403, body: CASFake.page(errors: #"["账号已锁定"]"#))
        XCTAssertEqual(forbidden, .cannotLoginDirectly(.unknown), "only 200 and 401 are pages to read")
        let elsewhere = try await post(status: 302, body: Data(), headers: ["Location": "https://cas.gdbtu.edu.cn/cas/somewhere"])
        XCTAssertEqual(elsewhere, .cannotLoginDirectly(.unknown))
    }

    func testWrongPasswordAndNoAnswerStayAsTheyWere() async throws {
        let wrong = try await post(status: 401, body: CASFake.page(errors: #"["用户名或密码错误，再错 3 次将锁定"]"#))
        XCTAssertEqual(wrong, .wrongCredentials)
        let vague = try await post(status: 401, body: CASFake.page(errors: #"["认证失败"]"#))
        XCTAssertEqual(vague, .wrongCredentials)
        let serverError = try await post(status: 502, body: Data("bad gateway".utf8))
        XCTAssertEqual(serverError, .noAnswer)
    }

    /// Only the captcha, extra check and password change are for the school's site.
    func testWhichOnesTheSchoolSiteClears() {
        XCTAssertEqual(SchoolLoginBlock.allCases.filter(\.needsSchoolSite), [.captcha, .mfa, .passwordChange])
    }
}
