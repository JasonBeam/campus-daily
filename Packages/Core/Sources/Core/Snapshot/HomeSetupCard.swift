import Foundation

/// 清爽 home's 「继续设置」 card: shown until the school account and the dorm are set (the washer is
/// not part of first-run setup); its small line names what the checklist covers.
public enum HomeSetupCard {
    public static let title = "继续设置"

    /// Nil when everything is set (no card).
    public static func detail(signedIn: Bool, dormSet: Bool) -> String? {
        signedIn && dormSet ? nil : "学校账号和宿舍"
    }
}
