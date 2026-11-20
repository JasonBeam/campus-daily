import Foundation

/// `count` taps, the first to the last within `window`.
public struct TapStreak: Sendable {
    public let count: Int
    public let window: Duration
    private var taps: [Date] = []

    public init(count: Int = 5, window: Duration = .seconds(3)) {
        self.count = count; self.window = window
    }

    /// True when this tap completes a streak (which then starts over).
    public mutating func register(at date: Date) -> Bool {
        taps.append(date)
        if taps.count > count { taps.removeFirst(taps.count - count) }
        guard taps.count == count, let first = taps.first else { return false }
        let seconds = Double(window.components.seconds) + Double(window.components.attoseconds) / 1e18
        guard date.timeIntervalSince(first) <= seconds else { return false }
        taps = []
        return true
    }
}
