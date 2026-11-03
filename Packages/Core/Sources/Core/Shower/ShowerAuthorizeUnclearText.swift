import Foundation

/// An authorize the platform answered in a way the app can't read (`authorizeUncertain`), or
/// with an authorization that can't be used (`authorizationInvalid`).
/// Nothing reached the controller, so no water ran and nothing is to be settled: the words say
/// the water didn't start, carry the platform's own sentence when it gave one, and keep the
/// check before the next start.
public enum ShowerAuthorizeUnclearText {
    public static let title = "水没开"
    public static let body = "学校那边没给准话，所以没开水。先去学校的热水记录里看看有没有多记一笔，看过了点「我在学校记录里核对过了」，再重新开始。"
    /// Siri and Shortcuts.
    public static let spoken = "水没开。打开校日常核对一下再开始。"

    public static func note(_ message: String) -> String { "学校提示：\(message)" }

    /// The status line, the lock screen and the home card.
    public static func title(platformMessage: String?) -> String {
        platformMessage.map { "\(title)。\(note($0))" } ?? title
    }

    public static func body(platformMessage: String?) -> String {
        platformMessage.map { body + note($0) } ?? body
    }

    public static func spoken(platformMessage: String?) -> String {
        guard let message = platformMessage else { return spoken }
        // The sentence goes on after it: one full stop, not two.
        let clause = String(message.reversed().drop(while: { $0 == "。" || $0 == "." }).reversed())
        return "\(title)。\(note(clause.isEmpty ? message : clause))。打开校日常核对一下再开始。"
    }
}
