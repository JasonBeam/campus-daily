import XCTest
@testable import Core

/// Five taps within three seconds, the first to the last.
final class TapStreakTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testFourTapsAreNotEnough() {
        var streak = TapStreak(count: 5, window: .seconds(3))
        for s in [0, 0.3, 0.6, 0.9] { XCTAssertFalse(streak.register(at: at(s))) }
    }

    func testFiveWithinTheWindowComplete() {
        var streak = TapStreak(count: 5, window: .seconds(3))
        for s in [0, 0.3, 0.6, 0.9] { XCTAssertFalse(streak.register(at: at(s))) }
        XCTAssertTrue(streak.register(at: at(1.2)))
    }

    func testTheFifthOutsideTheWindowDoesNot() {
        var streak = TapStreak(count: 5, window: .seconds(3))
        for s in [0.0, 1, 2, 3] { _ = streak.register(at: at(s)) }
        XCTAssertFalse(streak.register(at: at(3.5)), "first to fifth: 3.5 s")
    }

    /// The window slides: the last five taps count.
    func testTheWindowSlides() {
        var streak = TapStreak(count: 5, window: .seconds(3))
        for s in [0, 1, 2, 3.5, 4] { _ = streak.register(at: at(s)) }
        XCTAssertFalse(streak.register(at: at(4.5)), "1 … 4.5: 3.5 s")
        XCTAssertTrue(streak.register(at: at(4.9)), "2 … 4.9: 2.9 s")
    }

    /// A completed streak starts over: four more taps are not another.
    func testItStartsOverAfterCompleting() {
        var streak = TapStreak(count: 5, window: .seconds(3))
        for s in [0, 0.2, 0.4, 0.6] { _ = streak.register(at: at(s)) }
        XCTAssertTrue(streak.register(at: at(0.8)))
        for s in [1.0, 1.2, 1.4, 1.6] { XCTAssertFalse(streak.register(at: at(s)), "\(s)") }
        XCTAssertTrue(streak.register(at: at(1.8)))
    }
}
