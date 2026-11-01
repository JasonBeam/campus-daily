import Foundation

/// How many 「最近」 rows home shows: as many whole rows as fit under everything else, so home
/// never scrolls. Heights are measured in the view at the current text size.
public enum RecentFit {
    /// Rows shown before anything is measured (and the least wanted when they fit).
    public static let minimumRows = 3
    /// From the last row to the bottom of the safe area.
    public static let bottomGap: Double = 24

    /// `viewport`: the visible height; `above`: everything over the first row; `rowHeights`: each
    /// row as drawn (separator included), in order. Not measured yet (a zero): three rows. Fewer
    /// than three when only fewer fit: home does not scroll. None fits (everything above is
    /// already taller than the screen, at accessibility text sizes): home scrolls anyway, and
    /// three rows follow rather than 「最近」 alone.
    public static func count(viewport: Double, above: Double, rowHeights: [Double], bottomGap: Double = bottomGap) -> Int {
        guard viewport > 0, rowHeights.allSatisfy({ $0 > 0 }) else { return min(minimumRows, rowHeights.count) }
        // Measured heights are fractions of a point: half a point either way still fits.
        var left = viewport - above - bottomGap + 0.5
        var count = 0
        for height in rowHeights {
            guard height <= left else { break }
            left -= height
            count += 1
        }
        return count > 0 ? count : min(minimumRows, rowHeights.count)
    }
}
