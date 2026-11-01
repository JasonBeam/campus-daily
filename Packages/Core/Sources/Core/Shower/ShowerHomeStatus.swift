import Foundation

/// Where hot water stands, as the home shower button shows it.
public enum ShowerHomeStatus: Equatable, Sendable {
    case unconfigured
    /// Hot water can't be used in this build or at this school (no start); the reason is the subtitle.
    case unavailable(String)
    case idle
    case starting
    case showering(Date)
    case settling(Date)
    /// A record that needs checking before another start (stage label).
    case unresolved(String)
    /// The controller showed itself stopped while the record says water runs (「核对上次洗澡」).
    case needsCheck
    public var showering: Date? {
        switch self { case .showering(let date), .settling(let date): return date; default: return nil }
    }

    /// The home button asks for the school sign-in only when hot water is not in use: a shower
    /// that is starting, running, settling or waiting to be checked keeps its button (its end
    /// and settle are on it) whether or not the school login is there.
    public func asksForSchoolSignIn(signedIn: Bool) -> Bool {
        guard !signedIn else { return false }
        switch self {
        case .idle, .unconfigured, .unavailable: return true
        case .starting, .showering, .settling, .unresolved, .needsCheck: return false
        }
    }
}
