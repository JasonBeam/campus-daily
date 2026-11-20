import Foundation

/// `count` taps in a row, each within `gap` of the one before; a longer pause starts over.
public struct TapStreak: Sendable {
    public let count: Int
    public let gap: Duration
    private var last: Date?
    private var run = 0

    public init(count: Int = 5, gap: Duration = .seconds(1)) {
        self.count = count; self.gap = gap
    }

    /// True when this tap completes a streak (which then starts over).
    public mutating func register(at date: Date) -> Bool {
        let seconds = Double(gap.components.seconds) + Double(gap.components.attoseconds) / 1e18
        if let last, date >= last, date.timeIntervalSince(last) <= seconds { run += 1 } else { run = 1 }
        last = date
        guard run >= count else { return false }
        run = 0; last = nil
        return true
    }

    /// Forgets the taps so far.
    public mutating func reset() { run = 0; last = nil }
}
