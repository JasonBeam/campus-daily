import XCTest
@testable import Core

/// Frames inside the recharge and school-login pages go through the same host allow-list as
/// the page itself.
final class WebFrameAllowListTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }
    private let ecykt = "ecykt.gdbtu.edu.cn"

    func testRechargeFrameOnSchoolHostLoads() {
        XCTAssertEqual(RechargeNavigation.decide(url("https://ecykt.gdbtu.edu.cn/ykt-view/frame"), isUserTap: false, sourceHost: ecykt, isMainFrame: false), .allow)
        XCTAssertEqual(RechargeNavigation.decide(url("https://cas.gdbtu.edu.cn/cas/x"), isUserTap: false, sourceHost: ecykt, isMainFrame: false), .allow)
    }

    func testRechargeFrameFromAnotherHostIsCancelled() {
        XCTAssertEqual(RechargeNavigation.decide(url("https://pay.example.invalid/h5"), isUserTap: false, sourceHost: ecykt, isMainFrame: false), .cancel)
        XCTAssertEqual(RechargeNavigation.decide(url("http://ecykt.gdbtu.edu.cn/"), isUserTap: false, sourceHost: ecykt, isMainFrame: false), .cancel)
        XCTAssertEqual(RechargeNavigation.decide(url("data:text/html,x"), isUserTap: false, sourceHost: ecykt, isMainFrame: false), .cancel)
    }

    func testRechargeFrameNeverOpensAPayApp() {
        XCTAssertEqual(RechargeNavigation.decide(url("alipays://platformapi/startapp"), isUserTap: true, sourceHost: ecykt, isMainFrame: false), .cancel)
        XCTAssertEqual(RechargeNavigation.decide(url("weixin://wap/pay"), isUserTap: true, sourceHost: ecykt, isMainFrame: false), .cancel)
        XCTAssertEqual(RechargeNavigation.decide(url("alipays://platformapi/startapp"), isUserTap: true, sourceHost: ecykt, isMainFrame: true), .openExternal)
    }

    func testEmptyAndInlineFramesLoad() {
        XCTAssertEqual(RechargeNavigation.decide(url("about:blank"), isUserTap: false, sourceHost: ecykt, isMainFrame: false), .allow)
        XCTAssertEqual(RechargeNavigation.decide(url("about:srcdoc"), isUserTap: false, sourceHost: ecykt, isMainFrame: false), .allow)
        XCTAssertTrue(SchoolLoginNavigation.allows(url("about:blank"), isMainFrame: false))
        XCTAssertTrue(SchoolLoginNavigation.allows(url("about:srcdoc"), isMainFrame: false))
        XCTAssertFalse(SchoolLoginNavigation.allows(url("about:blank"), isMainFrame: true))
    }

    func testLoginPageAndFramesStayOnSchoolHosts() {
        for frame in [true, false] {
            XCTAssertTrue(SchoolLoginNavigation.allows(url("https://cas.gdbtu.edu.cn/cas/login"), isMainFrame: frame))
            XCTAssertTrue(SchoolLoginNavigation.allows(url("https://portal.gdbtu.edu.cn/"), isMainFrame: frame))
            XCTAssertTrue(SchoolLoginNavigation.allows(url("https://ecykt.gdbtu.edu.cn/"), isMainFrame: frame))
            XCTAssertTrue(SchoolLoginNavigation.allows(url("https://CAS.gdbtu.edu.cn:443/cas/login"), isMainFrame: frame))
            XCTAssertFalse(SchoolLoginNavigation.allows(url("https://captcha.example.invalid/"), isMainFrame: frame))
            XCTAssertFalse(SchoolLoginNavigation.allows(url("http://cas.gdbtu.edu.cn/"), isMainFrame: frame))
            XCTAssertFalse(SchoolLoginNavigation.allows(url("https://cas.gdbtu.edu.cn:8443/"), isMainFrame: frame))
            XCTAssertFalse(SchoolLoginNavigation.allows(url("https://u:p@cas.gdbtu.edu.cn/"), isMainFrame: frame))
            XCTAssertFalse(SchoolLoginNavigation.allows(url("https://cas.gdbtu.edu.cn.example.invalid/"), isMainFrame: frame))
        }
    }
}
