import XCTest
import Core

/// 「最近」 shows the whole rows that fit in the height left on home, so home never scrolls.
final class RecentFitTests: XCTestCase {
    let rows = Array(repeating: 56.0, count: 20)

    func testAsManyWholeRowsAsFitAboveTheBottomGap() {
        // 800 visible, 400 above, 24 gap: 376 left = 6 rows of 56 (336), a seventh would need 392.
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: rows), 6)
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400 - 16, rowHeights: rows), 7, "exactly fits")
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400 - 15, rowHeights: rows), 6, "no half row")
        XCTAssertEqual(RecentFit.bottomGap, 24)
    }

    func testNoMoreRowsThanThereAre() {
        XCTAssertEqual(RecentFit.count(viewport: 2000, above: 300, rowHeights: Array(rows.prefix(5))), 5)
        XCTAssertEqual(RecentFit.count(viewport: 2000, above: 300, rowHeights: []), 0)
    }

    /// Rows differ at large text (a title on two lines): each is counted at its own height.
    func testRowsOfDifferentHeights() {
        // 376 left: 100 + 120 + 90 = 310 fits, + 80 = 390 does not.
        XCTAssertEqual(RecentFit.count(viewport: 700, above: 300, rowHeights: [100, 120, 90, 80, 100]), 3)
        XCTAssertEqual(RecentFit.count(viewport: 700, above: 300, rowHeights: [100, 120, 90, 66, 100]), 4)
    }

    /// Fewer than three fit (a small phone at a large text size): fewer rows rather than a
    /// scrolling home.
    func testFewerThanThreeRatherThanScrolling() {
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 440, rowHeights: rows), 2)
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 520, rowHeights: rows), 1)
    }

    /// Not even one row fits (accessibility text sizes: everything above is taller than the
    /// screen): home scrolls anyway, so 「最近」 is not left as a header alone; three rows follow.
    func testThreeRowsBelowWhenHomeScrollsAnyway() {
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 560, rowHeights: rows), 3)
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 1400, rowHeights: rows), 3)
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 1400, rowHeights: [80]), 1)
    }

    /// Before the first measurement: three rows (fewer if there are fewer).
    func testThreeRowsBeforeAnythingIsMeasured() {
        XCTAssertEqual(RecentFit.minimumRows, 3)
        XCTAssertEqual(RecentFit.count(viewport: 0, above: 0, rowHeights: rows), 3)
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: [0, 0, 0, 0]), 3, "rows not measured yet")
        XCTAssertEqual(RecentFit.count(viewport: 0, above: 0, rowHeights: [56, 56]), 2)
    }

    /// Measured heights come in fractions of a point: a row that fits within half a point counts.
    func testHalfAPointOfRounding() {
        XCTAssertEqual(RecentFit.count(viewport: 800.4, above: 400, rowHeights: Array(repeating: 62.7, count: 10)), 6, "376.2 of 376.4")
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: [188.3, 188.0]), 2, "376.3 fits 376")
    }
}
