import Foundation

/// `count` taps, the first to the last within `window`.
public struct TapStreak: Sendable {
    public let count: Int
    public let window: Duration

    public init(count: Int = 5, window: Duration = .seconds(3)) {
        self.count = count; self.window = window
    }

    /// True when this tap completes a streak (which then starts over).
    // Red-phase stub: never completes.
    public mutating func register(at date: Date) -> Bool { false }
}
