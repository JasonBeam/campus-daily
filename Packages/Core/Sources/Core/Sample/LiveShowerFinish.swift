import Foundation

/// The end of a real shower from outside the app's pages: the Live Activity's button and
/// Siri/Shortcuts' 结束并结算. While the sample is shown it is left first (the live app is shown
/// again, not the login step), then the live session is ended; the app stays on the live pages.
@MainActor public enum LiveShowerFinish {
    public static func run<T>(sample: SampleMode?, _ end: @MainActor () async throws -> T) async rethrows -> T {
        if let sample, sample.isActive { sample.leaveForLive() }
        return try await end()
    }
}
