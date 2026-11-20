import Foundation

/// Why 开始洗澡 is greyed out on the hot-water page, said in the line under the button (both
/// themes) instead of the hint for a start, with a link where something can be done about it.
/// Exactly the states `ShowerLinkRule.mayStart` refuses: nil when a start may go.
/// Not signed in to the school is not one of them (home shows its sign-in button instead).
public enum ShowerStartBlock: Sendable, Equatable, CaseIterable {
    /// No dorm and controller bound.
    case notConfigured
    /// The build carries no hot-water profile.
    case platformMissing
    /// The school account signed out or changed: the dorm's controller is set up again first.
    case accountChanged
    /// The last 退出登录 did not complete while hot water was held for it.
    case signOutUnfinished
    /// The read-only controller check runs.
    case inspecting
    /// Something else talks to the controller (a check, an end) right now.
    case busy
    /// The phone can't save the shower record.
    case storage
    /// The saved shower record can't be read by this build.
    case recordUnreadable
    /// The last shower's record isn't finished (closing or settling).
    case unsettled
    /// The app is still loading what a start needs: no reason, a spinner on the button after
    /// `spinnerDelay`.
    case launching
    /// The campus card's balance is below zero and debt isn't allowed on this phone.
    case balanceNegative

    /// What the model knows when the button is drawn.
    public struct Facts: Sendable, Equatable {
        public var configured: Bool
        /// The launch's profile load has finished.
        public var profileLoaded: Bool
        /// Bound, with the profile loaded or not, and no profile.
        public var platformMissing: Bool
        public var residenceReview: Bool
        public var failedSignOut: Bool
        public var recordUnreadable: Bool
        public var storageBlocked: Bool
        public var engineReady: Bool
        public var inspecting: Bool
        public var busy: Bool
        /// The record allows a start (`ShowerState.canStart`).
        public var canStart: Bool
        /// `ShowerBalanceGate.blocks`.
        public var balanceBlocked: Bool
        public init(configured: Bool = true, profileLoaded: Bool = true, platformMissing: Bool = false,
                    residenceReview: Bool = false, failedSignOut: Bool = false, recordUnreadable: Bool = false,
                    storageBlocked: Bool = false, engineReady: Bool = true, inspecting: Bool = false,
                    busy: Bool = false, canStart: Bool = true, balanceBlocked: Bool = false) {
            self.balanceBlocked = balanceBlocked
            self.configured = configured; self.profileLoaded = profileLoaded; self.platformMissing = platformMissing
            self.residenceReview = residenceReview; self.failedSignOut = failedSignOut
            self.recordUnreadable = recordUnreadable; self.storageBlocked = storageBlocked
            self.engineReady = engineReady; self.inspecting = inspecting; self.busy = busy; self.canStart = canStart
        }
    }

    public static func of(_ f: Facts) -> ShowerStartBlock? {
        if f.recordUnreadable { return .recordUnreadable }
        if f.storageBlocked { return .storage }
        if !f.configured { return .notConfigured }
        if !f.profileLoaded { return .launching }
        if f.platformMissing { return .platformMissing }
        if f.residenceReview { return f.failedSignOut ? .signOutUnfinished : .accountChanged }
        if !f.engineReady { return .launching }
        if f.inspecting { return .inspecting }
        if f.busy { return .busy }
        if !f.canStart { return .unsettled }
        if f.balanceBlocked { return .balanceNegative }
        return nil
    }

    /// How long the button waits before it spins while the app is still loading, so a quick
    /// launch doesn't flash.
    public static let spinnerDelay: Duration = .milliseconds(300)

    /// The hint under 开始洗澡 while it can be tapped (暖橙; 清爽's is `ClearShowerText.startNote`).
    public static let warmNote = "点了开始，再按水控上的出水键。"

    /// What the reason's links open.
    public enum Link: Sendable, Equatable {
        /// The dorm and its controller, set (again).
        case dorm
        /// The same page, named for 核对水控 (setting the dorm again is what lets hot water go on).
        case checkController
        /// 学校账号, to sign out again.
        case settings
        /// 校园卡记录 (暖橙 only).
        case cardRecords
        /// 校园充值 (the campus card's top-up page).
        case topUp
    }

    public func links(clear: Bool) -> [Link] {
        switch self {
        case .notConfigured: return [.dorm]
        case .accountChanged: return [.checkController]
        case .signOutUnfinished: return [.settings, .checkController]
        case .recordUnreadable: return clear ? [] : [.cardRecords]
        case .balanceNegative: return [.topUp]
        case .platformMissing, .inspecting, .busy, .storage, .unsettled, .launching: return []
        }
    }

    public static func linkTitle(_ link: Link, clear: Bool) -> String {
        switch link {
        case .dorm: return clear ? "选择宿舍" : "选宿舍"
        case .checkController: return "核对水控"
        case .settings: return "去设置"
        case .cardRecords: return "看校园卡记录"
        case .topUp: return clear ? "前往校园充值" : "去充值"
        }
    }

    /// The line under the button (暖橙). Nil while launching.
    public var warm: String? {
        switch self {
        case .notConfigured: return "选好宿舍后就能用热水。"
        case .platformMissing: return "这个版本没带热水配置，热水暂时用不了，等下一版。"
        case .accountChanged: return "学校账号退出或换过，先重新核对宿舍的水控。"
        case .signOutUnfinished: return "上次退出学校账号没完成，热水暂时开不了。去设置里再退一次，或者重新核对宿舍的水控。"
        case .inspecting: return "正在核对水控，好了就能开始。"
        case .busy: return "正在处理，等一下就好。"
        case .storage: return "这台手机暂时存不了热水记录，重启 App 后再试。"
        case .recordUnreadable: return "读不到热水记录。去校园卡记录里看看这次扣了没有，扣费要 1 小时左右才出现。"
        case .unsettled: return "上一次洗澡还没结算完，结完才能开始新的。"
        case .launching: return nil
        // Without the amount (`text(clear:balance:)` says it).
        case .balanceNegative: return "校园卡欠费了，充上再来洗。"
        }
    }

    /// The line under the button (清爽). Nil while launching.
    public var clear: String? {
        switch self {
        case .notConfigured: return "选择宿舍后可使用热水"
        case .platformMissing: return "当前版本缺少热水配置，暂不可用；请等待后续版本"
        case .accountChanged: return "学校账号已退出或更换；请先重新核对宿舍水控"
        case .signOutUnfinished: return "上次退出学校账号未完成，暂不能开始洗澡；请在设置中重新退出，或重新核对宿舍水控"
        case .inspecting: return "正在核对水控；完成后可开始洗澡"
        case .busy: return "正在处理；请稍候"
        case .storage: return "这台手机暂时存不了热水记录，重启 App 后再试"
        case .recordUnreadable: return "读不到热水记录；可在校园卡消费明细中核对，扣费约 1 小时后入账"
        case .unsettled: return "上一次洗澡尚未结算完成；结算后可开始新的洗澡"
        case .launching: return nil
        // Without the amount (`text(clear:balance:)` says it).
        case .balanceNegative: return "校园卡已欠费；请充值后再开始洗澡"
        }
    }

    public func text(clear: Bool) -> String? { clear ? self.clear : warm }

    /// The line under the button with the card's balance where the reason is the balance
    /// (`balanceLine`); the other reasons' as `text(clear:)`.
    public func text(clear: Bool, balance: Money?) -> String? {
        if self == .balanceNegative, let balance { return Self.balanceLine(balance, clear:clear) }
        return text(clear:clear)
    }

    /// `.balanceNegative`'s line for a balance below zero: what the card owes, 「¥0.50」 as home
    /// writes the card's number (清爽 gives the balance itself, 「-¥0.50」).
    public static func balanceLine(_ balance: Money, clear: Bool) -> String {
        let owed = "¥" + balance.magnitudeYuanText
        return clear ? "校园卡余额 -\(owed)；请充值后再开始洗澡" : "校园卡欠了 \(owed)，充上再来洗。"
    }

    /// The page's headline (暖橙); nil keeps the page's own.
    public var warmTitle: String? {
        switch self {
        case .accountChanged: return "先重新核对水控"
        case .signOutUnfinished: return "热水暂时开不了"
        case .platformMissing: return "热水暂时用不了"
        case .notConfigured: return "还没设置热水"
        case .storage: return "暂时存不了热水记录"
        case .balanceNegative: return "校园卡欠费了"
        case .recordUnreadable, .unsettled, .inspecting, .busy, .launching: return nil
        }
    }

    /// The page's headline (清爽); nil keeps the page's own.
    public var clearTitle: String? {
        switch self {
        case .accountChanged: return "需要重新核对水控"
        case .signOutUnfinished: return "暂不能开始洗澡"
        case .platformMissing: return "热水暂不可用"
        case .notConfigured: return "尚未配置热水"
        case .storage: return "热水记录暂不可用"
        case .balanceNegative: return "校园卡已欠费"
        case .recordUnreadable, .unsettled, .inspecting, .busy, .launching: return nil
        }
    }

    public func title(clear: Bool) -> String? { clear ? clearTitle : warmTitle }

    /// The short line under 清爽's headline while greyed out (the reason itself is under the
    /// button); 暖橙 leaves it empty.
    public var clearHeadlineLine: String {
        switch self {
        case .accountChanged: return "学校账号已变更"
        default: return ""
        }
    }

    /// 暖橙's home capsule still reads 开始洗澡 and opens the hot-water page: its caption says why.
    /// Only for the reasons that last (the others pass, or have no capsule).
    public var showsOnHome: Bool { self == .accountChanged || self == .signOutUnfinished }

    /// The line under the page's headline said this already (or close to it): it is left out
    /// there, the reason under the button says it.
    public var replacesStatus: Bool {
        switch self {
        case .notConfigured, .platformMissing, .storage, .recordUnreadable: return true
        default: return false
        }
    }
}
