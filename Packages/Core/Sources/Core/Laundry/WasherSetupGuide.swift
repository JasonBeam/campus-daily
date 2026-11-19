import Foundation

/// The card at the top of the common-washer page: what to do first. Gone once signed in with a
/// machine saved.
public enum WasherSetupGuide: Sendable, Equatable {
    /// 「第一步：用手机号登录 U净」 with 「登录 U净」.
    case signIn
    /// 「下一步：扫描机身二维码」.
    case scan

    public static func card(signedIn: Bool, hasSavedMachine: Bool) -> WasherSetupGuide? {
        guard signedIn else { return .signIn }
        return hasSavedMachine ? nil : .scan
    }
}
