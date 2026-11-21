//
//  TapStreakTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
@testable import Core

/// Five taps, each within one second of the one before.
final class TapStreakTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testTheDefaultIsFiveWithinOneSecondEach() {
        let streak = TapStreak()
        XCTAssertEqual(streak.count, 5)
        XCTAssertEqual(streak.gap, .seconds(1))
    }

    func testFourTapsAreNotEnough() {
        var streak = TapStreak()
        for s in [0, 0.3, 0.6, 0.9] { XCTAssertFalse(streak.register(at: at(s))) }
    }

    func testFiveEachWithinTheGapComplete() {
        var streak = TapStreak()
        for s in [0, 0.3, 0.6, 0.9] { XCTAssertFalse(streak.register(at: at(s))) }
        XCTAssertTrue(streak.register(at: at(1.2)))
    }

    /// Slow but steady: each tap 1.0 s after the last still counts (4 s from first to fifth).
    func testAGapOfExactlyOneSecondCounts() {
        var streak = TapStreak()
        for s in [0.0, 1, 2, 3] { XCTAssertFalse(streak.register(at: at(s))) }
        XCTAssertTrue(streak.register(at: at(4)))
    }

    /// A pause longer than the gap starts over: that tap is the first of a new streak.
    func testALongerGapStartsOver() {
        var streak = TapStreak()
        for s in [0, 0.2, 0.4, 0.6] { XCTAssertFalse(streak.register(at: at(s))) }
        XCTAssertFalse(streak.register(at: at(1.7)), "1.1 s after the fourth")
        for s in [2.0, 2.3, 2.6] { XCTAssertFalse(streak.register(at: at(s)), "\(s)") }
        XCTAssertTrue(streak.register(at: at(2.9)), "the fifth since the pause")
    }

    /// A completed streak starts over: four more taps are not another.
    func testItStartsOverAfterCompleting() {
        var streak = TapStreak()
        for s in [0, 0.2, 0.4, 0.6] { _ = streak.register(at: at(s)) }
        XCTAssertTrue(streak.register(at: at(0.8)))
        for s in [1.0, 1.2, 1.4, 1.6] { XCTAssertFalse(streak.register(at: at(s)), "\(s)") }
        XCTAssertTrue(streak.register(at: at(1.8)))
    }

    func testResetForgetsTheTaps() {
        var streak = TapStreak()
        for s in [0, 0.2, 0.4, 0.6] { _ = streak.register(at: at(s)) }
        streak.reset()
        XCTAssertFalse(streak.register(at: at(0.8)))
    }

    /// A clock that went back doesn't extend a streak.
    func testAnEarlierTapStartsOver() {
        var streak = TapStreak()
        for s in [0, 0.2, 0.4, 0.6] { _ = streak.register(at: at(s)) }
        XCTAssertFalse(streak.register(at: at(0.1)))
    }
}
