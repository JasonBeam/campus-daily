import Foundation

/// 清爽 home's 「最近」: a header over a card of rows, last on a page laid out in one column at
/// most `maxWidth` wide (its padding included) with `pagePadding` inside it. Rows wrap at the card's
/// width less their own inset, so they are measured at `cardWidth`, never the screen's width;
/// then as many whole rows show as fit (`RecentFit`), so home never scrolls below the
/// accessibility sizes. None fit: the header and the card go too.
public struct RecentCardFit: Sendable, Equatable {
    /// The page's padding on every side (the bottom one ends the page under the card).
    public var pagePadding: Double
    /// The page's column, padding included, is at most this wide (iPad).
    public var maxWidth: Double
    /// A row's content starts and ends this far inside the card.
    public var rowInset: Double
    /// Space between the section above and the header.
    public var gapAbove: Double
    /// Space between the header and the card.
    public var headerGap: Double

    public init(pagePadding: Double, maxWidth: Double, rowInset: Double, gapAbove: Double, headerGap: Double) {
        self.pagePadding = pagePadding; self.maxWidth = maxWidth; self.rowInset = rowInset
        self.gapAbove = gapAbove; self.headerGap = headerGap
    }

    /// 清爽 home: padding 20, column 560, rows 16 in, 18 between sections, 8 under the header.
    public static let clearHome = RecentCardFit(pagePadding: 20, maxWidth: 560, rowInset: 16, gapAbove: 18, headerGap: 8)

    /// The card's width on a screen (the scroll view) this wide: the width rows are measured at.
    public func cardWidth(screen: Double) -> Double {
        max(0, min(screen, maxWidth) - 2 * pagePadding)
    }

    /// The width a row's symbol, text and amount share inside the card.
    public func rowContentWidth(screen: Double) -> Double {
        max(0, cardWidth(screen: screen) - 2 * rowInset)
    }

    /// `viewport`: the visible height; `above`: the bottom of the section over 「最近」, from the
    /// top of the page (its top padding included); `header`: the header's own height;
    /// `rowHeights`: each row measured at `cardWidth`, its separator included. At accessibility
    /// sizes home scrolls anyway: three rows.
    public func count(viewport: Double, above: Double, header: Double, rowHeights: [Double], accessibilitySize: Bool) -> Int {
        if accessibilitySize { return min(RecentFit.minimumRows, rowHeights.count) }
        return RecentFit.count(viewport: viewport, above: above, header: header, chrome: gapAbove + headerGap,
                               rowHeights: rowHeights, bottomGap: pagePadding)
    }
}
