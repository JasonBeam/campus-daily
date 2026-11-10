import Foundation

/// Where a balance on home goes (both themes, the same conditions as before 校园充值).
public enum CampusTopUpEntry: Sendable, Equatable {
    /// The 校园充值 page.
    case topUp
    /// The meter picker: electricity without a meter has nothing to top up yet.
    case bindMeter
    /// The login step of the first-run guide.
    case signIn

    /// 清爽's link under each balance, the same for both.
    public static let link = "充值 ›"

    /// The card balance (暖橙's figure): the page once signed in.
    public static func card(signedIn: Bool) -> CampusTopUpEntry { signedIn ? .topUp : .signIn }
    /// The electricity (暖橙's figure): the page once a meter is bound, the meter picker before.
    public static func power(signedIn: Bool, meterBound: Bool) -> CampusTopUpEntry {
        guard signedIn else { return .signIn }
        return meterBound ? .topUp : .bindMeter
    }
    /// 清爽's 「充值 ›」 under the card balance; nil hides it.
    public static func cardLink(signedIn: Bool) -> String? { card(signedIn: signedIn) == .topUp ? link : nil }
    /// 清爽's 「充值 ›」 under the electricity; nil hides it.
    public static func powerLink(signedIn: Bool, meterBound: Bool) -> String? {
        power(signedIn: signedIn, meterBound: meterBound) == .topUp ? link : nil
    }
}
