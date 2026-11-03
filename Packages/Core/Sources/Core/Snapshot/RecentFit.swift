import Foundation

/// How many 「最近」 rows home shows: as many whole rows as fit under everything else and the
/// section's header, so they never make home scroll. Heights are measured in the view at the
/// current text size.
public enum RecentFit {
    /// Rows shown before anything is measured (and the least wanted when they fit).
    public static let minimumRows = 3
    /// From the last row to the bottom of the safe area.
    public static let bottomGap: Double = 24

    /// `viewport`: the visible height; `above`: everything over the section; `header`: the
    /// section's header (its gap above included); `rowHeights`: each row as drawn (separator
    /// included), in order. Not measured yet (a zero): three rows. Fewer than three when only
    /// fewer fit, and none when none fits (a small phone at a large text size).
    public static func count(viewport: Double, above: Double, header: Double = 0, rowHeights: [Double], bottomGap: Double = bottomGap) -> Int {
        guard viewport > 0, rowHeights.allSatisfy({ $0 > 0 }) else { return min(minimumRows, rowHeights.count) }
        // Measured heights are fractions of a point: half a point either way still fits.
        var left = viewport - above - header - bottomGap + 0.5
        var count = 0
        for height in rowHeights {
            guard height <= left else { break }
            left -= height
            count += 1
        }
        return count
    }

    /// Whether 「最近」 is shown at all: not as a header (and 全部) over no row.
    public static func showsSection(viewport: Double, above: Double, header: Double = 0, rowHeights: [Double], bottomGap: Double = bottomGap) -> Bool {
        count(viewport: viewport, above: above, header: header, rowHeights: rowHeights, bottomGap: bottomGap) > 0
    }
}
