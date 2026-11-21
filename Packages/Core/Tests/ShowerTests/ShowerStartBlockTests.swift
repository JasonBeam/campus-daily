//
//  ShowerStartBlockTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import XCTest
@testable import Core

/// A greyed-out 开始洗澡 says why, under the button, in both themes.
final class ShowerStartBlockTests: XCTestCase {
    /// Every combination the model can be in: a reason exactly when `ShowerLinkRule.mayStart`
    /// refuses, none when it allows.
    func testAReasonExactlyWhenTheStartIsRefused() {
        var checked = 0
        for bits in 0..<(1 << 11) {
            func on(_ i: Int) -> Bool { bits & (1 << i) != 0 }
            let f = ShowerStartBlock.Facts(configured:on(0), profileLoaded:on(1), platformMissing:on(2), residenceReview:on(3),
                                           failedSignOut:on(4), recordUnreadable:on(5), storageBlocked:on(6), engineReady:on(7),
                                           inspecting:on(8), busy:on(9), canStart:on(10))
            // What the model can't be in: no binding has no missing profile; a bound one before
            // the profile is read has none yet; an unreadable record blocks storage.
            if !f.configured && f.platformMissing { continue }
            if f.configured && !f.profileLoaded && !f.platformMissing { continue }
            if f.recordUnreadable && !f.storageBlocked { continue }
            let ready = f.configured && !f.platformMissing && !f.residenceReview && f.engineReady && !f.storageBlocked
            let may = ShowerLinkRule.mayStart(f.canStart ? .idle : ShowerState(phase:.running), ready:ready, busy:f.busy, inspecting:f.inspecting)
            XCTAssertEqual(ShowerStartBlock.of(f) == nil, may, "\(f)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 500)
    }

    func testEachState() {
        typealias F = ShowerStartBlock.Facts
        XCTAssertNil(ShowerStartBlock.of(F()))
        XCTAssertEqual(ShowerStartBlock.of(F(configured:false)), .notConfigured)
        XCTAssertEqual(ShowerStartBlock.of(F(platformMissing:true)), .platformMissing)
        XCTAssertEqual(ShowerStartBlock.of(F(residenceReview:true)), .accountChanged)
        XCTAssertEqual(ShowerStartBlock.of(F(residenceReview:true, failedSignOut:true)), .signOutUnfinished)
        XCTAssertNil(ShowerStartBlock.of(F(failedSignOut:true)), "the flag means nothing without the review")
        XCTAssertEqual(ShowerStartBlock.of(F(inspecting:true)), .inspecting)
        XCTAssertEqual(ShowerStartBlock.of(F(busy:true)), .busy)
        XCTAssertEqual(ShowerStartBlock.of(F(storageBlocked:true)), .storage)
        XCTAssertEqual(ShowerStartBlock.of(F(recordUnreadable:true, storageBlocked:true)), .recordUnreadable)
        XCTAssertEqual(ShowerStartBlock.of(F(canStart:false)), .unsettled)
    }

    /// Launching: the profile or the engine isn't there yet. No reason, a spinner later.
    func testLaunchingSaysNothing() {
        typealias F = ShowerStartBlock.Facts
        XCTAssertEqual(ShowerStartBlock.of(F(profileLoaded:false, platformMissing:true)), .launching,
                       "a bound dorm before the profile is read is not a missing profile")
        XCTAssertEqual(ShowerStartBlock.of(F(engineReady:false)), .launching)
        XCTAssertEqual(ShowerStartBlock.of(F(configured:false, profileLoaded:false)), .notConfigured,
                       "no dorm is known at once")
        XCTAssertNil(ShowerStartBlock.launching.warm)
        XCTAssertNil(ShowerStartBlock.launching.clear)
        XCTAssertEqual(ShowerStartBlock.spinnerDelay, .milliseconds(300))
    }

    /// Which reason wins when several hold.
    func testOrder() {
        typealias F = ShowerStartBlock.Facts
        XCTAssertEqual(ShowerStartBlock.of(F(residenceReview:true, busy:true)), .accountChanged)
        XCTAssertEqual(ShowerStartBlock.of(F(platformMissing:true, residenceReview:true)), .platformMissing)
        XCTAssertEqual(ShowerStartBlock.of(F(residenceReview:true, storageBlocked:true)), .storage)
        XCTAssertEqual(ShowerStartBlock.of(F(inspecting:true, busy:true)), .inspecting)
        XCTAssertEqual(ShowerStartBlock.of(F(busy:true, canStart:false)), .busy)
    }

    func testWarmLines() {
        XCTAssertEqual(ShowerStartBlock.notConfigured.warm, "选好宿舍后就能用热水。")
        XCTAssertEqual(ShowerStartBlock.platformMissing.warm, "这个版本没带热水配置，热水暂时用不了，等下一版。")
        XCTAssertEqual(ShowerStartBlock.accountChanged.warm, "学校账号退出或换过，先重新核对宿舍的水控。")
        XCTAssertEqual(ShowerStartBlock.signOutUnfinished.warm, "上次退出学校账号没完成，热水暂时开不了。去设置里再退一次，或者重新核对宿舍的水控。")
        XCTAssertEqual(ShowerStartBlock.inspecting.warm, "正在核对水控，好了就能开始。")
        XCTAssertEqual(ShowerStartBlock.busy.warm, "正在处理，等一下就好。")
        XCTAssertEqual(ShowerStartBlock.storage.warm, "这台手机暂时存不了热水记录，重启 App 后再试。")
        XCTAssertEqual(ShowerStartBlock.recordUnreadable.warm, "读不到热水记录。去校园卡记录里看看这次扣了没有，扣费要 1 小时左右才出现。")
        XCTAssertEqual(ShowerStartBlock.unsettled.warm, "上一次洗澡还没结算完，结完才能开始新的。")
    }

    func testClearLines() {
        XCTAssertEqual(ShowerStartBlock.notConfigured.clear, "选择宿舍后可使用热水")
        XCTAssertEqual(ShowerStartBlock.platformMissing.clear, "当前版本缺少热水配置，暂不可用；请等待后续版本")
        XCTAssertEqual(ShowerStartBlock.accountChanged.clear, "学校账号已退出或更换；请先重新核对宿舍水控")
        XCTAssertEqual(ShowerStartBlock.signOutUnfinished.clear, "上次退出学校账号未完成，暂不能开始洗澡；请在设置中重新退出，或重新核对宿舍水控")
        XCTAssertEqual(ShowerStartBlock.inspecting.clear, "正在核对水控；完成后可开始洗澡")
        XCTAssertEqual(ShowerStartBlock.busy.clear, "正在处理；请稍候")
        XCTAssertEqual(ShowerStartBlock.recordUnreadable.clear, "读不到热水记录；可在校园卡消费明细中核对，扣费约 1 小时后入账")
        XCTAssertEqual(ShowerStartBlock.unsettled.clear, "上一次洗澡尚未结算完成；结算后可开始新的洗澡")
        // 清爽 has no sentence-final 。.
        for block in ShowerStartBlock.allCases { XCTAssertFalse(block.clear?.hasSuffix("。") ?? false, "\(block)") }
        for block in ShowerStartBlock.allCases where block != .launching { XCTAssertTrue(block.warm?.hasSuffix("。") ?? false, "\(block)") }
    }

    func testLinks() {
        XCTAssertEqual(ShowerStartBlock.notConfigured.links(clear:false), [.dorm])
        XCTAssertEqual(ShowerStartBlock.accountChanged.links(clear:true), [.checkController])
        XCTAssertEqual(ShowerStartBlock.signOutUnfinished.links(clear:false), [.settings, .checkController])
        XCTAssertEqual(ShowerStartBlock.recordUnreadable.links(clear:false), [.cardRecords])
        XCTAssertEqual(ShowerStartBlock.recordUnreadable.links(clear:true), [])
        for block in [ShowerStartBlock.inspecting, .busy, .platformMissing, .launching, .storage, .unsettled] {
            XCTAssertEqual(block.links(clear:false), [], "\(block): nothing to do")
            XCTAssertEqual(block.links(clear:true), [], "\(block): nothing to do")
        }
        XCTAssertEqual(ShowerStartBlock.linkTitle(.dorm, clear:false), "选宿舍")
        XCTAssertEqual(ShowerStartBlock.linkTitle(.dorm, clear:true), "选择宿舍")
        XCTAssertEqual(ShowerStartBlock.linkTitle(.checkController, clear:true), "核对水控")
        XCTAssertEqual(ShowerStartBlock.linkTitle(.settings, clear:false), "去设置")
    }

    func testTitles() {
        XCTAssertEqual(ShowerStartBlock.accountChanged.title(clear:false), "先重新核对水控")
        XCTAssertEqual(ShowerStartBlock.accountChanged.title(clear:true), "需要重新核对水控")
        XCTAssertEqual(ShowerStartBlock.signOutUnfinished.title(clear:false), "热水暂时开不了")
        XCTAssertEqual(ShowerStartBlock.signOutUnfinished.title(clear:true), "暂不能开始洗澡")
        XCTAssertEqual(ShowerStartBlock.platformMissing.title(clear:false), "热水暂时用不了")
        XCTAssertEqual(ShowerStartBlock.platformMissing.title(clear:true), "热水暂不可用")
        XCTAssertEqual(ShowerStartBlock.notConfigured.title(clear:false), "还没设置热水")
        XCTAssertEqual(ShowerStartBlock.notConfigured.title(clear:true), "尚未配置热水")
        XCTAssertEqual(ShowerStartBlock.storage.title(clear:false), "暂时存不了热水记录")
        XCTAssertEqual(ShowerStartBlock.storage.title(clear:true), "热水记录暂不可用")
        for block in [ShowerStartBlock.recordUnreadable, .unsettled, .inspecting, .busy, .launching] {
            XCTAssertNil(block.title(clear:false), "\(block) keeps the page's title")
            XCTAssertNil(block.title(clear:true), "\(block) keeps the page's title")
        }
        // Never the ready titles while greyed out.
        for block in ShowerStartBlock.allCases {
            XCTAssertNotEqual(block.title(clear:false), "准备洗澡")
            XCTAssertNotEqual(block.title(clear:true), ClearShowerText.readyTitle)
        }
        XCTAssertEqual(ShowerStartBlock.accountChanged.clearHeadlineLine, "学校账号已变更")
    }

    /// 暖橙's home capsule says why only for the account's reasons.
    func testHomeCaption() {
        XCTAssertEqual(ShowerStartBlock.allCases.filter(\.showsOnHome), [.accountChanged, .signOutUnfinished])
    }

    /// The line under the headline doesn't say the reason a second time.
    func testReasonsThatReplaceTheStatusLine() {
        XCTAssertEqual(ShowerStartBlock.allCases.filter(\.replacesStatus), [.notConfigured, .platformMissing, .storage, .recordUnreadable])
    }

    /// The hint while 开始洗澡 can be tapped: nobody has done an 授权.
    func testStartNotes() {
        XCTAssertEqual(ShowerStartBlock.warmNote, "点了开始，再按水控上的出水键。")
        XCTAssertEqual(ClearShowerText.startNote, "开始后，按水控上的出水键")
    }
}
