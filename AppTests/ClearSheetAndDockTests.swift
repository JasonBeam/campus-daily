//
//  ClearSheetAndDockTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import XCTest
import SwiftUI
import Core
@testable import XiaoRiChang

/// View-level states of 清爽's pay sheet and shower dock.
@MainActor
final class ClearSheetAndDockTests: XCTestCase {
    /// Paying an order already placed shows machine, program, amount and note together: the
    /// half-height detent can't hold them on a small phone, so both sheets open full height.
    func testPaySheetOpensFullHeight() {
        XCTAssertEqual(ClearLaundryPaySheet.detents(asksMode:true), [.large])
        XCTAssertEqual(ClearLaundryPaySheet.detents(asksMode:false), [.large])
    }

    /// 开始洗澡 on a refused shower turns to 正在处理… at once, spinning and off, before the
    /// page's phase moves; as the starting look while the engine has the start.
    func testRefusedRetryShowsTheStartingLookAtOnce() {
        let idle = ClearShowerDock.retryFace(tapped:false, starting:false)
        XCTAssertEqual(idle.title, ClearShowerText.deniedRetry)
        XCTAssertFalse(idle.spinning)
        XCTAssertTrue(idle.enabled)
        for (tapped, starting) in [(true, false), (false, true), (true, true)] {
            let face = ClearShowerDock.retryFace(tapped:tapped, starting:starting)
            XCTAssertEqual(face.title, ClearShowerText.busyButton)
            XCTAssertTrue(face.spinning)
            XCTAssertFalse(face.enabled)
        }
    }
}
