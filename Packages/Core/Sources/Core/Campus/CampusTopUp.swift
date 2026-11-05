import Foundation

/// 校园充值: the school's own top-up, opened outside the app. The app never handles money: it
/// opens the school's WeChat service (「e广工商大办事大厅」) or the school's web hand-off page in
/// Safari, and reads the balances again once the user comes back.
public enum CampusTopUp {
    /// Issued by the school's own mini-program (Add to Home Screen), as upstream 0.9.0's
    /// OfficialCampusRechargeView has it.
    public static let weChat = URL(string: "weixin://dl/business/?t=I0xUgrvZt1g")!
    /// The school's hand-off page for the same service, opened in Safari.
    public static let web = URL(string: "https://wxmpurl.cn/I0xUgrvZt1g")!
}
