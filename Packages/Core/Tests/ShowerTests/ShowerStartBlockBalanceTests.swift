//
//  ShowerStartBlockBalanceTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

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

    /// Both themes say it under the button with what the card owes (copy v2 §1).
    func testItSaysWhyInBothThemes() {
        let owed = Money(fen:-50)
        XCTAssertEqual(ShowerStartBlock.balanceNegative.text(clear:false, balance:owed), "校园卡欠了 ¥0.50，充上再来洗。")
        XCTAssertEqual(ShowerStartBlock.balanceNegative.text(clear:true, balance:owed), "校园卡余额 -¥0.50；请充值后再开始洗澡")
        XCTAssertEqual(ShowerStartBlock.balanceLine(Money(fen:-12345), clear:false), "校园卡欠了 ¥123.45，充上再来洗。")
        XCTAssertEqual(ShowerStartBlock.balanceLine(Money(fen:-1), clear:true), "校园卡余额 -¥0.01；请充值后再开始洗澡")
        // Without the amount (never drawn: the balance is known when it refuses).
        XCTAssertTrue(ShowerStartBlock.balanceNegative.warm?.hasSuffix("。") ?? false, "暖橙 ends its sentences")
        XCTAssertFalse(ShowerStartBlock.balanceNegative.clear?.hasSuffix("。") ?? true, "清爽 has no sentence-final 。")
        XCTAssertEqual(ShowerStartBlock.balanceNegative.text(clear:true, balance:nil), ShowerStartBlock.balanceNegative.clear)
        // Another reason ignores the balance.
        XCTAssertEqual(ShowerStartBlock.busy.text(clear:false, balance:owed), ShowerStartBlock.busy.warm)
    }

    /// The most a card could owe: formatted from the unsigned magnitude, no trap at `Int.min`.
    func testTheLineAtTheLimits() {
        XCTAssertEqual(ShowerStartBlock.balanceLine(Money(fen:.min), clear:false), "校园卡欠了 ¥92233720368547758.08，充上再来洗。")
        XCTAssertEqual(ShowerStartBlock.balanceLine(Money(fen:.min), clear:true), "校园卡余额 -¥92233720368547758.08；请充值后再开始洗澡")
        XCTAssertEqual(Money(fen:.min).yuanText, "-92233720368547758.08")
        XCTAssertEqual(Money(fen:.max).yuanText, "92233720368547758.07")
        XCTAssertEqual(Money(fen:-50).magnitudeYuanText, "0.50")
        XCTAssertEqual(Money(fen:0).yuanText, "0.00")
    }

    /// Its headline, and one link: the campus card's top-up page.
    func testTitleAndTopUpLink() {
        XCTAssertEqual(ShowerStartBlock.balanceNegative.title(clear:false), "校园卡欠费了")
        XCTAssertEqual(ShowerStartBlock.balanceNegative.title(clear:true), "校园卡已欠费")
        XCTAssertEqual(ShowerStartBlock.balanceNegative.links(clear:false), [.topUp])
        XCTAssertEqual(ShowerStartBlock.balanceNegative.links(clear:true), [.topUp])
        XCTAssertEqual(ShowerStartBlock.linkTitle(.topUp, clear:false), "去充值")
        XCTAssertEqual(ShowerStartBlock.linkTitle(.topUp, clear:true), "前往校园充值")
    }

    /// Not a reason that replaces the headline's status line.
    func testItLeavesTheStatusLine() {
        XCTAssertFalse(ShowerStartBlock.balanceNegative.replacesStatus)
    }
}
