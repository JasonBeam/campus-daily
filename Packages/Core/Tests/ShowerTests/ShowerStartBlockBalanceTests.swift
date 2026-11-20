import XCTest
@testable import Core

/// The balance reason under a greyed-out 开始洗澡 (`ShowerStartBlock.balanceNegative`): the last
/// of the reasons, so every other one says what is going on first.
final class ShowerStartBlockBalanceTests: XCTestCase {
    typealias F = ShowerStartBlock.Facts

    /// Every combination, now with the balance: a reason exactly when the link rule or the
    /// balance refuses, none when both allow.
    func testAReasonExactlyWhenTheStartOrTheBalanceRefuses() {
        var checked = 0
        var balanceOnly = 0
        for bits in 0..<(1 << 12) {
            func on(_ i: Int) -> Bool { bits & (1 << i) != 0 }
            let f = F(configured:on(0), profileLoaded:on(1), platformMissing:on(2), residenceReview:on(3),
                      failedSignOut:on(4), recordUnreadable:on(5), storageBlocked:on(6), engineReady:on(7),
                      inspecting:on(8), busy:on(9), canStart:on(10), balanceBlocked:on(11))
            if !f.configured && f.platformMissing { continue }
            if f.configured && !f.profileLoaded && !f.platformMissing { continue }
            if f.recordUnreadable && !f.storageBlocked { continue }
            let ready = f.configured && !f.platformMissing && !f.residenceReview && f.engineReady && !f.storageBlocked
            let may = ShowerLinkRule.mayStart(f.canStart ? .idle : ShowerState(phase:.running), ready:ready, busy:f.busy, inspecting:f.inspecting)
            XCTAssertEqual(ShowerStartBlock.of(f) == nil, may && !f.balanceBlocked, "\(f)")
            // The balance is the reason only when nothing else is.
            if may && f.balanceBlocked {
                XCTAssertEqual(ShowerStartBlock.of(f), .balanceNegative, "\(f)")
                balanceOnly += 1
            } else if !may {
                XCTAssertNotEqual(ShowerStartBlock.of(f), .balanceNegative, "another reason comes first: \(f)")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 1000)
        XCTAssertGreaterThan(balanceOnly, 0)
    }

    func testTheBalanceAlone() {
        XCTAssertEqual(ShowerStartBlock.of(F(balanceBlocked:true)), .balanceNegative)
        XCTAssertNil(ShowerStartBlock.of(F(balanceBlocked:false)))
    }

    /// After every existing reason: account, storage, launching, checking, busy, unsettled.
    func testEveryOtherReasonComesFirst() {
        XCTAssertEqual(ShowerStartBlock.of(F(residenceReview:true, balanceBlocked:true)), .accountChanged)
        XCTAssertEqual(ShowerStartBlock.of(F(residenceReview:true, failedSignOut:true, balanceBlocked:true)), .signOutUnfinished)
        XCTAssertEqual(ShowerStartBlock.of(F(configured:false, balanceBlocked:true)), .notConfigured)
        XCTAssertEqual(ShowerStartBlock.of(F(platformMissing:true, balanceBlocked:true)), .platformMissing)
        XCTAssertEqual(ShowerStartBlock.of(F(storageBlocked:true, balanceBlocked:true)), .storage)
        XCTAssertEqual(ShowerStartBlock.of(F(recordUnreadable:true, storageBlocked:true, balanceBlocked:true)), .recordUnreadable)
        XCTAssertEqual(ShowerStartBlock.of(F(engineReady:false, balanceBlocked:true)), .launching)
        XCTAssertEqual(ShowerStartBlock.of(F(profileLoaded:false, platformMissing:true, balanceBlocked:true)), .launching)
        XCTAssertEqual(ShowerStartBlock.of(F(inspecting:true, balanceBlocked:true)), .inspecting)
        XCTAssertEqual(ShowerStartBlock.of(F(busy:true, balanceBlocked:true)), .busy)
        XCTAssertEqual(ShowerStartBlock.of(F(canStart:false, balanceBlocked:true)), .unsettled)
    }

    /// The last case: the order of `allCases` puts it after the reasons that come before it.
    func testItIsTheLastCase() {
        XCTAssertEqual(ShowerStartBlock.allCases.last, .balanceNegative)
    }

    /// Both themes say it under the button (the words are Camo's; here only that they say
    /// 余额 and 充值, the way the brief asks), as the other reasons do.
    func testItSaysWhyInBothThemes() {
        let warm = ShowerStartBlock.balanceNegative.warm
        let clear = ShowerStartBlock.balanceNegative.clear
        XCTAssertNotNil(warm)
        XCTAssertNotNil(clear)
        for line in [warm, clear].compactMap({ $0 }) {
            XCTAssertTrue(line.contains("余额"), line)
            XCTAssertTrue(line.contains("充值"), line)
        }
        XCTAssertTrue(warm?.hasSuffix("。") ?? false, "暖橙 ends its sentences")
        XCTAssertFalse(clear?.hasSuffix("。") ?? true, "清爽 has no sentence-final 。")
    }

    /// Not a reason that replaces the headline's status line.
    func testItLeavesTheStatusLine() {
        XCTAssertFalse(ShowerStartBlock.balanceNegative.replacesStatus)
    }
}
