//
//  WebFrameAllowListTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import XCTest
@testable import Core

/// Frames inside the school-login page go through the same host allow-list as the page itself.
final class WebFrameAllowListTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testEmptyAndInlineFramesLoad() {
        XCTAssertTrue(SchoolLoginNavigation.allows(url("about:blank"), isMainFrame: false))
        XCTAssertTrue(SchoolLoginNavigation.allows(url("about:srcdoc"), isMainFrame: false))
        XCTAssertFalse(SchoolLoginNavigation.allows(url("about:blank"), isMainFrame: true))
    }

    func testLoginFrameFromAnotherHostOrSchemeIsCancelled() {
        XCTAssertFalse(SchoolLoginNavigation.allows(url("https://pay.example.invalid/h5"), isMainFrame: false))
        XCTAssertFalse(SchoolLoginNavigation.allows(url("data:text/html,x"), isMainFrame: false))
        XCTAssertFalse(SchoolLoginNavigation.allows(url("weixin://wap/pay"), isMainFrame: true))
        XCTAssertFalse(SchoolLoginNavigation.allows(url("alipays://platformapi/startapp"), isMainFrame: false))
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
