//
//  ShowerBalanceGateTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
@testable import Core

/// 开始洗澡 is refused while the campus card's balance is below zero, unless debt is allowed on
/// this phone. No balance (nothing this app read for the person signed in now) never refuses;
/// which reads count is `CardBalanceReadTests`.
final class ShowerBalanceGateTests: XCTestCase {
    private let afterLaunch = Date(timeIntervalSince1970: 1_800_000_030)

    private func balance(_ fen: Int) -> ShowerBalance { ShowerBalance(amount: Money(fen: fen), readAt: afterLaunch) }

    // MARK: blocks

    func testMinusFiftyFenBlocks() {
        XCTAssertTrue(ShowerBalanceGate.blocks(balance(-50), allowsDebt: false))
        XCTAssertTrue(ShowerBalanceGate.blocks(ShowerBalance(amount: Money(yuanString: "-0.50")!, readAt: afterLaunch), allowsDebt: false),
                      "−0.5 as the school writes it")
        XCTAssertTrue(ShowerBalanceGate.blocks(balance(-1), allowsDebt: false), "one fen below zero")
    }

    func testAllowedDebtLetsMinusFiftyFenStart() {
        XCTAssertFalse(ShowerBalanceGate.blocks(balance(-50), allowsDebt: true))
    }

    func testZeroPositiveAndUnknownNeverBlock() {
        XCTAssertFalse(ShowerBalanceGate.blocks(balance(0), allowsDebt: false), "zero still showers")
        XCTAssertFalse(ShowerBalanceGate.blocks(balance(1), allowsDebt: false))
        XCTAssertFalse(ShowerBalanceGate.blocks(balance(8650), allowsDebt: false))
        XCTAssertFalse(ShowerBalanceGate.blocks(nil, allowsDebt: false), "not read: allowed")
        XCTAssertFalse(ShowerBalanceGate.blocks(nil, allowsDebt: true))
    }
}
