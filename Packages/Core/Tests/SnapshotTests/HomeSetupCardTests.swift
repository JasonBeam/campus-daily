//
//  HomeSetupCardTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import XCTest
import Core

/// 清爽 home's 「继续设置」 card: there until the account and the dorm are set. The washer is not
/// part of first-run setup, so an unbound one never keeps the card.
final class HomeSetupCardTests: XCTestCase {
    func testGoneWhenAccountAndDormAreSet() {
        XCTAssertNil(HomeSetupCard.detail(signedIn: true, dormSet: true), "no washer needed: setup no longer asks about laundry")
    }

    func testShownWhileAccountOrDormIsMissing() {
        XCTAssertEqual(HomeSetupCard.detail(signedIn: false, dormSet: true),
                       "学校账号和宿舍")
        XCTAssertEqual(HomeSetupCard.detail(signedIn: true, dormSet: false),
                       "学校账号和宿舍")
        XCTAssertEqual(HomeSetupCard.detail(signedIn: false, dormSet: false),
                       "学校账号和宿舍")
        XCTAssertEqual(HomeSetupCard.title, "继续设置")
    }
}
