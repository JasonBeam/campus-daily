import XCTest
import Core
@testable import XiaoRiChang

/// A password login the school did not call wrong is said by its cause, in both themes: a lock
/// (wait 5 minutes), something for the school's site (「去学校官网处理」 opens Safari), or a page we
/// don't know. Each time 登录 stays the primary button and can be sent again; the web login is
/// only the small link under the form.
final class SchoolLoginCauseTests: XCTestCase {
    func state(_ block: SchoolLoginBlock) -> SchoolLoginState {
        SchoolLoginState(after:SchoolLoginFailure.cannotLoginDirectly(block))
    }

    func testEachBlockIsSaidByItsCause() {
        XCTAssertEqual(state(.locked), .blocked(.locked))
        XCTAssertEqual(state(.captcha), .blocked(.needsSchoolSite))
        XCTAssertEqual(state(.mfa), .blocked(.needsSchoolSite))
        XCTAssertEqual(state(.passwordChange), .blocked(.needsSchoolSite))
        XCTAssertEqual(state(.unknown), .blocked(.unknown))
        XCTAssertEqual(SchoolLoginState(after:SchoolLoginFailure.wrongCredentials), .wrong)
        XCTAssertEqual(SchoolLoginState(after:SchoolLoginFailure.noAnswer), .failed(ServiceError.offline.userMessage))
    }

    func testTheWarmLines() {
        XCTAssertEqual(state(.locked).message(.warm), "错的次数太多，学校把账号锁了。等 5 分钟再登。")
        XCTAssertEqual(state(.captcha).message(.warm), "学校要你先在官网处理一下，比如验证或改密码。弄好了回来再登。")
        XCTAssertEqual(state(.unknown).message(.warm), "这次没法直接登录，可能是学校登录页变了。过一会儿再试，急的话用下面的学校网页登录。")
        XCTAssertEqual(SchoolLoginText.schoolSite(.warm), "去学校官网处理")
        XCTAssertEqual(SchoolLoginText.webLogin(.warm), "用学校网页登录")
        XCTAssertEqual(SchoolLoginText.wrong, "账号或密码不对，再试一次。")
    }

    func testTheClearLines() {
        XCTAssertEqual(state(.locked).message(.clear), "账号已被锁定，请 5 分钟后再登录")
        XCTAssertEqual(state(.mfa).message(.clear), "学校要求先在官网完成验证或修改密码，完成后返回重新登录")
        XCTAssertEqual(state(.unknown).message(.clear), "暂时无法直接登录，可稍后重试或使用学校网页登录")
        XCTAssertEqual(SchoolLoginText.schoolSite(.clear), "前往学校官网")
        XCTAssertEqual(SchoolLoginText.webLogin(.clear), "使用学校网页登录")
    }

    /// Only the school-site cause has the Safari button, and it opens the school's own login page.
    func testOnlyTheSchoolSiteCauseOffersSafari() {
        XCTAssertTrue(state(.captcha).offersSchoolSite)
        for other: SchoolLoginState in [.idle, .loading, .wrong, .blocked(.locked), .blocked(.unknown), .failed("x")] {
            XCTAssertFalse(other.offersSchoolSite, "\(other)")
        }
        XCTAssertEqual(SchoolSiteButton.url.scheme, "https")
        XCTAssertEqual(SchoolSiteButton.url.host, SchoolEndpoints.casHost)
        XCTAssertEqual(SchoolSiteButton.url.path, "/cas/login")
    }

    /// A lock keeps 保存密码 (the same login is tried later); the other two causes hide it.
    func testTheSaveCheckShowsForALockOnly() {
        XCTAssertTrue(SchoolLoginState.blocked(.locked).showsSaveCheck)
        XCTAssertFalse(SchoolLoginState.blocked(.needsSchoolSite).showsSaveCheck)
        XCTAssertFalse(SchoolLoginState.blocked(.unknown).showsSaveCheck)
        XCTAssertTrue(SchoolLoginState.idle.showsSaveCheck)
        XCTAssertTrue(SchoolLoginState.wrong.showsSaveCheck)
    }

    /// Never stuck: after any cause the password login can be sent again, and the primary
    /// button is 登录 (never the web login).
    func testTheDirectLoginStaysRetryable() {
        for cause in [SchoolLoginCause.locked, .needsSchoolSite, .unknown] {
            XCTAssertTrue(SchoolLoginState.blocked(cause).allowsDirectLogin, "\(cause)")
        }
        XCTAssertFalse(SchoolLoginState.loading.allowsDirectLogin)
        XCTAssertEqual(SchoolLoginText.primary(loggingIn:false), "登录")
        XCTAssertEqual(SchoolLoginText.primary(loggingIn:true), "正在登录…")
    }
}
