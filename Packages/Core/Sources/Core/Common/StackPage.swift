import Foundation

/// A page on one of 清爽's tab stacks, as the stack rules (`PageStack`) need to know it: which is
/// the shower page, which the dorm page (where hot water is bound), and which may hold the user
/// in a payment.
public protocol StackPage: Equatable {
    /// 热水洗澡.
    static var showerPage: Self { get }
    /// 宿舍, where the hot-water controller is bound.
    static var dormPage: Self { get }
    /// A top-up page (校园卡, 电费): coming back from paying must find it.
    var isTopUp: Bool { get }
    /// 洗衣, which holds an order being paid.
    var isLaundry: Bool { get }
}
