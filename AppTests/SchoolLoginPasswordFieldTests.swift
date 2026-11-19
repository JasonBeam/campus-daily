import XCTest
import Core
@testable import XiaoRiChang

/// The login forms (first run, 重新登录学校账号, 清爽's setup) clear the typed password once it
/// was used up: signed in, or refused as wrong. Anything else leaves it to try again.
final class SchoolLoginPasswordFieldTests: XCTestCase {
    func testAWrongPasswordIsClearedLikeASignIn() {
        XCTAssertTrue(SchoolLoginState.wrong.clearsTypedPassword)
        XCTAssertTrue(SchoolLoginState.idle.clearsTypedPassword)
        XCTAssertEqual(SchoolLoginState.wrong.message(.warm), SchoolLoginText.wrong)
        XCTAssertEqual(SchoolLoginState.wrong.message(.clear), SchoolLoginText.wrong)
        XCTAssertEqual(SchoolLoginText.wrong, "账号或密码不对，再试一次。")
    }

    func testOtherAnswersKeepThePassword() {
        for state: SchoolLoginState in [.loading, .blocked(.locked), .blocked(.needsSchoolSite),
                                         .blocked(.unknown), .failed(SchoolLoginText.busy)] {
            XCTAssertFalse(state.clearsTypedPassword, "\(state)")
        }
    }
}
