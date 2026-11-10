import Foundation

/// 清爽 home's 「继续设置」 card: shown until the school account, the dorm and, while 学校洗衣机
/// is on, the usual washer are set; its small line names what the checklist covers.
public enum HomeSetupCard {
    public static let title = "继续设置"

    /// Nil when everything is set (no card).
    public static func detail(signedIn: Bool, dormSet: Bool, laundryEnabled: Bool, laundryBound: Bool) -> String? {
        let done = signedIn && dormSet && (!laundryEnabled || laundryBound)
        guard !done else { return nil }
        return laundryEnabled ? "学校账号、宿舍和常用洗衣机" : "学校账号和宿舍"
    }
}
