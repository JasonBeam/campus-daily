import Foundation

/// The platform definitely turned the authorize down (`authorizeRefused`: 4002, -301, or before
/// sending): nothing was issued, and those answers carry no sentence of the platform's.
public enum ShowerAuthorizeRefusedText {
    /// The page, the status line and the lock screen.
    public static let title = "水没开成"
    /// Siri and Shortcuts.
    public static let spoken = "学校没让开水，打开校日常看看。"
}
