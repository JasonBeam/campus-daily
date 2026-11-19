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

    /// Not even one row fits under everything else: no row, so a small phone at a large text
    /// size does not get rows pushed off the screen.
    func testNoRowWhenNoneFits() {
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 560, rowHeights: rows), 0)
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 1400, rowHeights: rows), 0)
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 1400, rowHeights: [80]), 0)
    }

    /// No row fits: the section goes, header and 全部 too, rather than a header over nothing.
    func testNoSectionWhenNoRowFits() {
        XCTAssertFalse(RecentFit.showsSection(viewport: 600, above: 560, rowHeights: rows))
        XCTAssertFalse(RecentFit.showsSection(viewport: 600, above: 1400, rowHeights: [80]))
        XCTAssertFalse(RecentFit.showsSection(viewport: 2000, above: 300, rowHeights: []), "nothing to show")
        XCTAssertTrue(RecentFit.showsSection(viewport: 600, above: 520, rowHeights: rows), "one row")
        XCTAssertTrue(RecentFit.showsSection(viewport: 0, above: 0, rowHeights: rows), "not measured yet")
    }

    /// The screen is measured but no row is yet (the first layout): no section until one is,
    /// rather than three rows that may not fit and then jump.
    func testNoSectionUntilARowIsMeasured() {
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: [0, 0, 0, 0]), 0)
        XCTAssertFalse(RecentFit.showsSection(viewport: 800, above: 400, rowHeights: [0, 0]))
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: [56, 56]), 2, "all measured")
    }

    /// A new record arrives on top and is not measured yet: the section stays, counted as if
    /// each unmeasured row were as tall as the tallest measured one, so 「最近」 doesn't vanish
    /// for a frame on every refresh that brings a record.
    func testANewUnmeasuredRowKeepsTheSection() {
        // 376 left: six rows of 56 with or without the new one on top.
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: [0] + rows), 6)
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: [56, 56, 0, 56]), 4)
        XCTAssertTrue(RecentFit.showsSection(viewport: 800, above: 400, rowHeights: [0, 56]))
        // Counted at the tallest measured row: never more rows than may fit.
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: [0, 0, 100, 56, 56, 56]), 4, "100 × 3 + 56 = 356 fits, a fifth row would need 412")
    }

    /// The header counts against the screen too: it fits, but no row fits under it, so the
    /// section goes. `above` is where the section starts, over its header.
    func testHeaderThatFitsOverNoRowHidesTheSection() {
        // 600 - 500 - 24 = 76 would take one 56 row; under a 40 header only 36 is left.
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 500, rowHeights: rows), 1)
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 500, header: 40, rowHeights: rows), 0)
        XCTAssertFalse(RecentFit.showsSection(viewport: 600, above: 500, header: 40, rowHeights: rows))
        // 800 - 400 - 40 - 24 = 336: six rows under the header.
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, header: 40, rowHeights: rows), 6)
        XCTAssertTrue(RecentFit.showsSection(viewport: 800, above: 400, header: 40, rowHeights: rows))
    }

    /// Before the first measurement: three rows (fewer if there are fewer).
    func testThreeRowsBeforeAnythingIsMeasured() {
        XCTAssertEqual(RecentFit.minimumRows, 3)
        XCTAssertEqual(RecentFit.count(viewport: 0, above: 0, rowHeights: rows), 3)
        XCTAssertEqual(RecentFit.count(viewport: 0, above: 0, rowHeights: [56, 56]), 2)
    }

    /// Measured heights come in fractions of a point: a row that fits within half a point counts.
    func testHalfAPointOfRounding() {
        XCTAssertEqual(RecentFit.count(viewport: 800.4, above: 400, rowHeights: Array(repeating: 62.7, count: 10)), 6, "376.2 of 376.4")
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, rowHeights: [188.3, 188.0]), 2, "376.3 fits 376")
    }

    /// 清爽 draws 「最近」 in a card: its padding above and below the rows counts against the
    /// screen like the header, so a row that fits on the flat page may not fit in the card.
    func testCardChromeCountsAgainstTheScreen() {
        // 800 - 400 - 40 - 24 = 336: six rows flat; with 28 of card padding 308 is left, five.
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, header: 40, rowHeights: rows), 6)
        XCTAssertEqual(RecentFit.count(viewport: 800, above: 400, header: 40, chrome: 28, rowHeights: rows), 5)
        // One row fits flat under the header, none inside the card: no section.
        XCTAssertEqual(RecentFit.count(viewport: 600, above: 480, header: 40, rowHeights: rows), 1)
        XCTAssertFalse(RecentFit.showsSection(viewport: 600, above: 480, header: 40, chrome: 28, rowHeights: rows))
        // Before the first measurement the chrome changes nothing.
        XCTAssertEqual(RecentFit.count(viewport: 0, above: 0, chrome: 28, rowHeights: rows), 3)
    }
}
