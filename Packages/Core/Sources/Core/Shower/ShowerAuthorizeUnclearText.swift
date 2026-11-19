import Foundation

/// An authorize the platform answered in a way the app can't read (`authorizeUncertain`), or
/// with an authorization that can't be used (`authorizationInvalid`).
/// Nothing reached the controller, so no water ran and nothing is to be settled: the words say
/// the water didn't start and carry the platform's own sentence when it gave one. The record is
/// kept for the school like a stopped shower (`ShowerState.showerOver`).
public enum ShowerAuthorizeUnclearText {
    public static let title = "水没开"
    /// Siri and Shortcuts.
    public static let spoken = ShowerAuthorText.spokenNoWater

    public static func note(_ message: String) -> String { "学校提示：\(message)" }

    /// The status line, the lock screen and the home card.
    public static func title(platformMessage: String?) -> String {
        platformMessage.map { "\(title)。\(note($0))" } ?? title
    }

    public static func spoken(platformMessage: String?) -> String {
        guard let message = platformMessage else { return spoken }
        // The sentence goes on after it: one full stop, not two.
        let clause = String(message.reversed().drop(while: { $0 == "。" || $0 == "." }).reversed())
        return "\(title)。\(note(clause.isEmpty ? message : clause))。\(ShowerAuthorText.spokenRetry)"
    }
}
