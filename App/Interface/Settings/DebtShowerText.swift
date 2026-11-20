/// The words of the debt start setting (copy v2 §2, §3, §5): the system alert after five taps
/// on the version, and its group while it is on.
enum DebtShowerText {
    static let alertTitle = "输入口令"
    static let placeholder = "口令"
    static let cancel = "取消"
    static let confirm = "确定"
    static let symbol = "creditcard.trianglebadge.exclamationmark"

    static func title(clear: Bool) -> String { clear ? "允许欠费洗澡" : "欠费时也能洗澡" }

    static func footer(clear: Bool) -> String {
        clear ? "校园卡余额为负时仍可开始洗澡；欠费需后续充值补足；仅对本机有效"
            : "校园卡余额是负的也照样能开水，欠的钱之后还是要充上。只在这台手机上有效。"
    }

    /// Turned off, but the phone didn't store it (`ShowerModel.setAllowsDebt` returned false).
    static func unstored(clear: Bool) -> String {
        clear ? "已关闭，但未能保存；重新打开 App 后可能恢复开启，请重试"
            : "已经关了，但没存下来，重新打开 App 可能又会开着。"
    }

    static func retry(clear: Bool) -> String { clear ? "重试" : "再试一次" }
}
