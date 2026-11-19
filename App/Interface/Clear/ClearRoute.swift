import Foundation
import Core

/// A page pushed on one of 清爽's tab stacks. Every stack maps it with `ClearDestination`.
enum ClearRoute: Hashable {
    /// 热水洗澡: the whole shower, from 开始洗澡 to the result (`ClearShowerPage`).
    case shower
    /// 洗衣 (`ClearLaundryPage`).
    case laundry
    /// 常用洗衣机.
    case washerSetup
    /// 宿舍电费充值, or the meter picker while no meter is bound.
    case power
    /// 电表.
    case powerSetup
    /// 校园卡充值.
    case card
    /// 校园登录与宿舍 (the account, the dorm, the meter and hot water).
    case account
    /// 宿舍 (also where hot water is bound).
    case dorm
    /// 外观 › 主题.
    case theme
    /// 故障排查.
    case advanced
    /// 洗衣提醒 (洗衣结束提醒 and its 10-second test).
    case laundryReminders
    /// 其他提醒: power, card and unsettled-shower reminders.
    case reminders
    /// 快捷使用: how to add the shortcuts.
    case shortcuts
    /// 首次设置, pushed (from home's 继续设置 card and the settings tab's top row).
    case setupChecklist
}

/// What the stack rules (`PageStack`) need to know of a page.
extension ClearRoute: StackPage {
    static var showerPage: ClearRoute { .shower }
    static var dormPage: ClearRoute { .dorm }
    var isTopUp: Bool { self == .card || self == .power }
    var isLaundry: Bool { self == .laundry }
}
