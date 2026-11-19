import Foundation

/// The links the widget opens: campusdaily://home back to the home screen, campusdaily://login
/// (login expired, never signed in) straight to the sign-in, campusdaily://settings/account
/// (automatic login held off) to Settings › 学校账号. Any app can open them, so each root
/// ignores them while a top-up page or a laundry order being paid is open (`WidgetLink.mayClosePages`).
public enum RootLink: Equatable, Sendable {
    case home
    case login
    /// Any campusdaily://settings link; only `/account` opens a page.
    case settings(account: Bool)

    public init?(_ url: URL) {
        guard url.scheme == "campusdaily" else { return nil }
        switch url.host {
        case "home": self = .home
        case "login": self = .login
        case "settings": self = .settings(account: url.path == "/account")
        default: return nil
        }
    }
}
