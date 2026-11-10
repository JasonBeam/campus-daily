import Foundation

/// Copy and display rules for the 「U净 账号」 section and an expired U净 login.
public enum UjingAccountText {
    public static let title = "U净 账号"
    public static let phone = "手机号"
    public static let signOut = "退出 U净"
    public static let confirmTitle = "退出 U净？"
    public static let confirmMessage = "退出以后，要重新登录 U净 才能下单。"
    public static let confirm = "退出"
    public static let cancel = "取消"
    /// An expired login, wherever U净 said so, with the `relogin` button.
    public static let expired = "U净 登录过期了。"
    public static let relogin = "重新登录 U净"

    /// The first three and last four digits of an 11-digit number; anything else fully hidden.
    public static func maskedPhone(_ mobile: String) -> String {
        guard UjingInput.isMobile(mobile) else { return String(repeating: "*", count: max(mobile.count, 1)) }
        return String(mobile.prefix(3)) + "****" + String(mobile.suffix(4))
    }

    /// U净 refused a call because the login ran out.
    public static func isExpired(_ error: Error) -> Bool {
        (error as? ServiceError)?.isSessionExpired == true
    }
}
