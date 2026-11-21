//
//  ShowerIdentityFailureTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/17.
//

import XCTest
@testable import Core

/// Why the hot-water account read failed, as setup says it: the campus-card system turning the
/// hand-off down over the balance, or anything else (the hot-water platform's own refusals
/// included).
final class ShowerIdentityFailureTests: XCTestCase {
    func testTheCampusCardSystemTalkingAboutTheBalanceIsALowBalance() {
        for (code, message) in [("500", "账户余额不足，请充值后使用"), ("500", "余额不足"), ("1", "欠费"), ("7", "请先充值")] {
            XCTAssertEqual(ShowerIdentityFailure(ServiceError.rejection(.ecykt, code: code, message: message)), .lowBalance, message)
        }
    }

    func testEverythingElseIsGeneric() {
        let others: [Error] = [
            ServiceError.rejection(.lxt6, code: "1", message: "账户余额不足，请充值后使用"),
            ServiceError.rejection(.lxt6, code: "2", message: "欠费"),
            ServiceError.rejection(.lxt6, code: "1", message: "系统繁忙"),
            ServiceError.rejection(.ecykt, code: "500", message: "系统繁忙"),
            ServiceError.badRequest(.ecykt),
            ServiceError.sessionExpired(.ecykt),
            ServiceError.badRequest(.lxt6),
            ServiceError.malformed(.lxt6, "Data"),
            ServiceError.offline,
            CancellationError(),
        ]
        for error in others { XCTAssertEqual(ShowerIdentityFailure(error), .other, "\(error)") }
    }

    func testTheLines() {
        XCTAssertEqual(ShowerIdentityFailure.lowBalance.warmText,
                       "学校校园卡系统说余额不足，这次没绑上热水。给校园卡充值后，到设置的「热水」里再绑。电费和校园卡余额照常能看。")
        XCTAssertEqual(ShowerIdentityFailure.lowBalance.clearText,
                       "校园卡系统提示余额不足，暂未绑定热水；校园卡充值后可在设置 › 校园登录与宿舍 › 宿舍热水中重新绑定，电费与校园卡余额查询不受影响")
        XCTAssertEqual(ShowerIdentityFailure.other.warmText, "这次没读到热水账号，先跳过。之后到设置的「热水」里再绑，电费和校园卡照常用。")
        XCTAssertEqual(ShowerIdentityFailure.other.clearText,
                       "热水账号读取失败，暂未绑定热水；可在设置 › 校园登录与宿舍 › 宿舍热水中重新绑定，电费与校园卡不受影响")
    }
}
