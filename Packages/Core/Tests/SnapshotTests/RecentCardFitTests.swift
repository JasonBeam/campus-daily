import XCTest
import Core

/// 清爽 home's 「最近」: rows in a card inside the page's padded column, measured at the width
/// they are drawn at, and only as many whole rows as fit without scrolling.
final class RecentCardFitTests: XCTestCase {
    let fit = RecentCardFit.clearHome
    let rows = Array(repeating: 56.0, count: 20)

    /// The card is the page's column: at most 560 wide, 20 in from each of its sides.
    func testCardIsThePagesColumn() {
        XCTAssertEqual(fit.cardWidth(screen: 402), 362, "18 Pro")
        XCTAssertEqual(fit.cardWidth(screen: 375), 335, "SE")
        XCTAssertEqual(fit.cardWidth(screen: 1024), 520, "iPad: the column's limit, less its padding")
        XCTAssertEqual(fit.cardWidth(screen: 30), 0, "never negative")
    }

    /// A row's text wraps inside the card's 16 pt row inset on each side, so it is narrower than
    /// the card, and narrower again on a narrower screen: rows are measured at the card's width,
    /// never the screen's.
    func testRowContentIsInsetInsideTheCard() {
        XCTAssertEqual(fit.rowContentWidth(screen: 402), 330)
        XCTAssertEqual(fit.rowContentWidth(screen: 375), 303)
        XCTAssertEqual(fit.rowContentWidth(screen: 320), 248, "narrower screen, narrower rows")
        XCTAssertEqual(fit.rowContentWidth(screen: 1024), 488)
        XCTAssertLessThan(fit.rowContentWidth(screen: 402), 402 - 2 * 16, "not the full width less the row inset")
    }

    /// Everything over the rows counts: what is above, the gap and the header, the gap under the
    /// header, and the page's bottom padding.
    func testWholeRowsUnderTheHeader() {
        // 700 - 400 - 18 - 20 - 8 - 20 = 234: four rows of 56 (224), a fifth would need 280.
        XCTAssertEqual(fit.count(viewport: 700, above: 400, header: 20, rowHeights: rows, accessibilitySize: false), 4)
        XCTAssertEqual(fit.count(viewport: 700, above: 400 - 46, header: 20, rowHeights: rows, accessibilitySize: false), 5,
                       "exactly fits")
        XCTAssertEqual(fit.count(viewport: 700, above: 400, header: 20, rowHeights: Array(rows.prefix(2)),
                                 accessibilitySize: false), 2, "no more than there are")
    }

    /// The same records measured at a narrower width wrap onto a second line and are taller:
    /// fewer of them fit, rather than a last row pushed under the tab bar.
    func testTallerRowsAtANarrowerWidthFitFewer() {
        let wide = [56.0, 56, 56, 56]
        let narrow = [74.0, 74, 74, 74]
        XCTAssertEqual(fit.count(viewport: 700, above: 400, header: 20, rowHeights: wide, accessibilitySize: false), 4)
        XCTAssertEqual(fit.count(viewport: 700, above: 400, header: 20, rowHeights: narrow, accessibilitySize: false), 3)
    }

    /// Not one row fits (a small phone): no rows, so the header and the card are hidden too.
    func testNoRowFitsHidesTheSection() {
        // 667 - 590 - 18 - 20 - 8 - 20 = 11: not one 56 row.
        XCTAssertEqual(fit.count(viewport: 667, above: 590, header: 20, rowHeights: rows, accessibilitySize: false), 0)
        XCTAssertEqual(fit.count(viewport: 667, above: 2000, header: 20, rowHeights: rows, accessibilitySize: false), 0)
    }

    /// Accessibility sizes: home scrolls anyway, so three rows whatever the screen.
    func testThreeRowsAtAccessibilitySizes() {
        XCTAssertEqual(fit.count(viewport: 667, above: 2000, header: 40, rowHeights: rows, accessibilitySize: true), 3)
        XCTAssertEqual(fit.count(viewport: 667, above: 2000, header: 40, rowHeights: [90], accessibilitySize: true), 1)
    }

    /// iPhone SE (375 × 667): status bar 20 and large title bar 96 above, the floating tab bar
    /// from 584 down, so 468 visible. In 清爽 home (normal demo) the tiles end 484 below the
    /// content's top at the default size and past the screen's bottom at xxxLarge: no row fits,
    /// so 最近's header and card are hidden.
    func testSENoRowAtDefaultOrXXXLarge() {
        let viewport = 584.0 - 20 - 96
        XCTAssertEqual(fit.cardWidth(screen: 375), 335)
        XCTAssertEqual(fit.count(viewport: viewport, above: 484, header: 20, rowHeights: rows, accessibilitySize: false), 0,
                       "default")
        XCTAssertEqual(fit.count(viewport: viewport, above: 590, header: 24, rowHeights: Array(repeating: 66, count: 6),
                                 accessibilitySize: false), 0, "xxxLarge")
    }

    /// iPhone 18 Pro (402 × 874): status bar 62 and large title bar 96 above, the tab bar from 791,
    /// so 633 visible. The tiles end 470 down at the default size: one row; 565 at xxxLarge: none.
    func testEighteenProOneRowAtDefaultNoneAtXXXLarge() {
        let viewport = 791.0 - 62 - 96
        XCTAssertEqual(fit.count(viewport: viewport, above: 470, header: 20, rowHeights: rows, accessibilitySize: false), 1,
                       "default: 633 - 470 - 18 - 20 - 8 - 20 = 97, one row of 56")
        XCTAssertEqual(fit.count(viewport: viewport, above: 565, header: 24, rowHeights: Array(repeating: 66, count: 6),
                                 accessibilitySize: false), 0, "xxxLarge")
    }
}
