//
//  ShowerDetailPillTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import SwiftUI
import XCTest
@testable import XiaoRiChang

/// 暖橙's 热水洗澡 button (`ShowerDetailPill`): home's black pill, the accent with the shower
/// page's ink while a shower can be ended, the standard greyed-out pill otherwise.
final class ShowerDetailPillTests: XCTestCase {
    func testTheLooks() {
        XCTAssertEqual(ShowerDetailPill.Look.of(closing:false, enabled:true), .start)
        XCTAssertEqual(ShowerDetailPill.Look.of(closing:true, enabled:true), .end)
        XCTAssertEqual(ShowerDetailPill.Look.of(closing:false, enabled:false), .disabled)
        XCTAssertEqual(ShowerDetailPill.Look.of(closing:true, enabled:false), .disabled)
    }

    func testStartIsHomesPill() {
        XCTAssertEqual(ShowerDetailPill.Look.start.background, Theme.pill)
        XCTAssertEqual(ShowerDetailPill.Look.start.ink(dark:false), Theme.pillInk)
        XCTAssertEqual(ShowerDetailPill.Look.start.ink(dark:true), Theme.pillInk)
    }

    func testEndIsTheAccentWithTheShowerPagesInk() {
        XCTAssertEqual(ShowerDetailPill.Look.end.background, Theme.accent)
        XCTAssertEqual(ShowerDetailPill.Look.end.ink(dark:false), .fixed(.white))
        XCTAssertEqual(ShowerDetailPill.Look.end.ink(dark:true), .fixed(Color(white:0.07)))
    }

    func testDisabledIsFillAndInk3() {
        XCTAssertEqual(ShowerDetailPill.Look.disabled.background, Theme.fill)
        XCTAssertEqual(ShowerDetailPill.Look.disabled.ink(dark:false), Theme.ink3)
    }

    func testSymbolsAndSize() {
        XCTAssertEqual(ShowerDetailPill.symbol(closing:false), "drop.fill")
        XCTAssertEqual(ShowerDetailPill.symbol(closing:true), "stop.circle")
        XCTAssertEqual(ShowerDetailPill.height, 56)
        XCTAssertEqual(ShowerDetailPill.pressedOpacity, 0.76)
    }
}
