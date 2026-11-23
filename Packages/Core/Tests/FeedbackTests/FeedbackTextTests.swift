//
//  FeedbackTextTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
import Core

/// The feedback form's lines for a slow send and for a failed one with screenshots, per theme.
final class FeedbackTextTests: XCTestCase {
    func testTheFailureLineSaysScreenshotsWhenThereWereSome() {
        XCTAssertEqual(FeedbackText.failure(withScreenshots: false, clear: false), FeedbackText.failureText)
        XCTAssertEqual(FeedbackText.failure(withScreenshots: false, clear: true), FeedbackText.failureText)
        XCTAssertEqual(FeedbackText.failure(withScreenshots: true, clear: false), "没发出去。网络慢的话，少带几张截图再试。")
        XCTAssertEqual(FeedbackText.failure(withScreenshots: true, clear: true), "发送失败；网络较慢时可减少截图后重试")
    }

    func testTheSlowLineSaysItIsStillSending() {
        XCTAssertEqual(FeedbackText.slowAfter, 5)
        XCTAssertEqual(FeedbackText.slow(clear: false), "网络有点慢，还在发。不想等可以点取消。")
        XCTAssertEqual(FeedbackText.slow(clear: true), "网络较慢，仍在发送；可点「取消」停止")
        for clear in [false, true] { XCTAssertFalse(FeedbackText.slow(clear: clear).contains("快好了")) }
    }
}
