import XCTest
@testable import Core

final class InterruptionStreakTests: XCTestCase {
    func testThreeInterruptionsInARowShowTheProblem() {
        var streak = InterruptionStreak()
        XCTAssertFalse(streak.record(.interrupted))
        XCTAssertFalse(streak.record(.interrupted))
        XCTAssertTrue(streak.record(.interrupted))
        XCTAssertTrue(streak.record(.interrupted), "still showing while it goes on")
    }

    func testAnyOtherAnswerEndsTheStreak() {
        for other: SchoolReading.Outcome in [.ok, .needsLogin(.offline), .failed(.offline), .notSignedIn] {
            var streak = InterruptionStreak()
            _ = streak.record(.interrupted); _ = streak.record(.interrupted)
            XCTAssertFalse(streak.record(other))
            XCTAssertEqual(streak.count, 0)
            XCTAssertFalse(streak.record(.interrupted))
        }
    }

    func testALostLeaseNeitherCountsNorResets() {
        var streak = InterruptionStreak()
        _ = streak.record(.interrupted); _ = streak.record(.interrupted)
        XCTAssertFalse(streak.record(.leaseLost))
        XCTAssertTrue(streak.record(.interrupted))
    }
}
