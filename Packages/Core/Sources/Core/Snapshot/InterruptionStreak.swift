import Foundation

/// Refreshes that ended `interrupted` one after another. One alone is nothing to show (the
/// password changed meanwhile, a write refused once); several in a row mean the Keychain keeps
/// refusing writes and the numbers only grow older, so the home screen says so.
public struct InterruptionStreak: Sendable, Equatable {
    /// Interrupted refreshes in a row before the problem is shown.
    public static let showAfter = 3
    public private(set) var count = 0

    public init() {}

    /// Counts one refresh's outcome; true while the problem should show. A lost lease says
    /// nothing about the Keychain and leaves the count alone; anything else ends the streak.
    public mutating func record(_ outcome: SchoolReading.Outcome) -> Bool {
        switch outcome {
        case .interrupted: count += 1
        case .leaseLost: break
        case .ok, .needsLogin, .failed, .notSignedIn: count = 0
        }
        return count >= Self.showAfter
    }
}
