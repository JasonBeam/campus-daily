//
//  ShowerRefusedFaceTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import XCTest
import Core
@testable import XiaoRiChang

/// The refused page in both themes: with 再试一次 / 开始洗澡 (A) and without (B).
final class ShowerRefusedFaceTests: XCTestCase {
    /// 暖橙: A and B send the user to 校园卡记录 for the last charge; in use keeps its own line.
    func testWarmBodyFollowsTheFace() {
        XCTAssertEqual(ShowerPageText.refusedBody(inUse:false, retryable:true),
                       "这次没扣钱。过一会儿再试，一直这样就去校园卡记录里看看上一次扣了没有。")
        XCTAssertEqual(ShowerPageText.refusedBody(inUse:false, retryable:false),
                       "学校没让开水，可能上一次还没结束。去校园卡记录里看看上一次扣了没有，过一会儿再来开。")
        XCTAssertEqual(ShowerPageText.refusedBody(inUse:true, retryable:true), ShowerPageText.inUseBody)
        XCTAssertEqual(ShowerPageText.refusedBody(inUse:true, retryable:false), ShowerPageText.inUseBody)
    }

    /// 清爽's B: 好 alone, centred, no arrow, where A's 开始洗澡 is. The settled face is as before.
    func testClearRefusedWithoutRetryHoldsTheRetrysPlace() {
        let refused = ClearShowerDock.answerFace(.denied)
        XCTAssertEqual(refused.title, "好")
        XCTAssertNil(refused.symbol)
        XCTAssertTrue(refused.centered)
        XCTAssertTrue(refused.holdsRetrySlot)
        let done = ClearShowerDock.answerFace(.done)
        XCTAssertEqual(done.title, "开始洗澡")
        XCTAssertEqual(done.symbol, "arrow.up.right")
        XCTAssertFalse(done.centered)
        XCTAssertFalse(done.holdsRetrySlot)
    }
}
