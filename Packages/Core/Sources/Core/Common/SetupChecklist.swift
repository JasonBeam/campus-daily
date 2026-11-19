import Foundation

/// 清爽's 首次配置 checklist: which rows it shows, which are done, how many of the needed ones
/// are done, which step a row or its button opens, and what each row says.
///
/// Rows in order: 学校账号, 选择宿舍与水控, both needed (「已完成 1 / 2」). Laundry is not asked:
/// it is on unless the 学校洗衣机 switch says otherwise, and machines are bound from home. The
/// controller is not checked here: that is done at the first 开始洗澡, which `doneNote` says.
public struct SetupChecklist: Equatable, Sendable {
    public enum Row: Hashable, CaseIterable, Sendable {
        case account, dorm
    }

    public var signedIn: Bool
    /// The dorm the user confirmed (「3 栋 108」); nil until then.
    public var dorm: String?
    public var controllerBound: Bool

    public init(signedIn: Bool, dorm: String?, controllerBound: Bool) {
        self.signedIn = signedIn; self.dorm = dorm; self.controllerBound = controllerBound
    }

    private var dormDone: Bool { signedIn && dorm != nil }

    public var rows: [Row] { needed }
    /// The rows the count is out of.
    private var needed: [Row] { [.account, .dorm] }

    public func isDone(_ row: Row) -> Bool {
        switch row {
        case .account: signedIn
        case .dorm: dormDone
        }
    }

    /// The step page a row opens: the dorm needs the account first.
    public func step(for row: Row) -> Row {
        row == .dorm && !signedIn ? .account : row
    }

    public var doneCount: Int { needed.filter(isDone).count }
    /// The first needed row not done; nil when both are.
    public var next: Row? { needed.first { !isDone($0) } }
    public var allDone: Bool { next == nil }
    /// For the progress bar, 0...1.
    public var fraction: Double { Double(doneCount) / Double(needed.count) }

    // MARK: Copy

    public static let navTitle = "首次配置"
    public static let later = "稍后设置"
    public static let footnote = "这里只读取和保存配置，不会出水、下单或付款。"
    public static let meterTitle = "宿舍电费与小组件"

    public static func meterDetail(bound: Bool) -> String { bound ? "电表已绑定，可更换" : "可选，完成后也能设置" }

    public static func title(_ row: Row) -> String {
        switch row {
        case .account: "学校账号"
        case .dorm: "选择宿舍与水控"
        }
    }

    public func detail(_ row: Row) -> String {
        switch row {
        case .account: return signedIn ? "已登录，可查询校园卡余额" : "登录后自动同步校园卡余额"
        case .dorm: return dorm.flatMap { dormDone ? $0.replacingOccurrences(of:" ", with:"") : nil } ?? "选好宿舍，热水和电费都按它来"
        }
    }

    /// 「已完成 1 / 2」.
    public var progress: String { "已完成 \(doneCount) / \(needed.count)" }
    /// The progress bar to VoiceOver: 「已完成 1 项，共两项」.
    public var spokenProgress: String { "已完成 \(doneCount) 项，共两项" }
    public var headline: String { allDone ? "都准备好了" : "完成首次设置" }
    public var hint: String {
        if !signedIn { return "先登录学校账号，再选择宿舍。" }
        if !dormDone { return "学校账号已登录，接着选择你的宿舍。" }
        return "宿舍已保存，可以开始使用。"
    }
    /// Under 「完成设置」 once both rows are done: the controller is checked at the first 开始洗澡.
    public var doneNote: String? {
        allDone ? "首次洗澡时请在水控旁点「开始洗澡」；会先核对是否为本宿舍水控" : nil
    }
    /// The button under the rows: on to the next needed row, or done.
    public var button: String {
        if allDone { return "完成设置" }
        return signedIn ? "继续选择宿舍" : "登录并连接校园卡"
    }

    /// UserDefaults key (String) of the dorm confirmed on the checklist; hot water may have no
    /// controller to bind, so a binding alone can't say the dorm was confirmed.
    public static let dormKey = PreferenceKey.prefix + "setup.dorm"

    /// Whether the dorm is set, for the checklist and home's 继续设置 card alike: a controller is
    /// bound to it, or it was confirmed here (`confirmedDorm`, stored at `dormKey`) and is still
    /// the dorm.
    public static func isDormSet(dorm: String?, confirmedDorm: String, controllerBound: Bool) -> Bool {
        controllerBound || dorm != nil && dorm == confirmedDorm
    }
}
