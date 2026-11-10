import Foundation

/// 清爽's 首次配置 checklist: which rows it shows, which are done, how many of the needed ones
/// are done, which step a row or its button opens, and what each row says.
///
/// Rows in order: 学校账号, 选择宿舍与水控, 洗衣机（可选）. The first two are needed (「已完成 1 / 2」);
/// the washers are optional, and 「不用」 (the 学校洗衣机 switch off) answers them. 水控 is not a
/// row: it is the check after the dorm step while the bound controller wasn't checked.
public struct SetupChecklist: Equatable, Sendable {
    public enum Row: Hashable, CaseIterable, Sendable {
        case account, dorm, laundry, controller
    }

    public enum Laundry: Equatable, Sendable {
        /// Not answered: on, with no machine saved yet.
        case open
        /// This many machines saved.
        case saved(Int)
        /// 「不用」.
        case notUsed
    }

    public var signedIn: Bool
    /// The dorm the user confirmed (「3 栋 108」); nil until then.
    public var dorm: String?
    public var laundry: Laundry
    public var controllerBound: Bool
    /// The bound controller was checked nearby.
    public var controllerChecked: Bool

    public init(signedIn: Bool, dorm: String?, laundry: Laundry, controllerBound: Bool, controllerChecked: Bool) {
        self.signedIn = signedIn; self.dorm = dorm; self.laundry = laundry
        self.controllerBound = controllerBound; self.controllerChecked = controllerChecked
    }

    private var dormDone: Bool { signedIn && dorm != nil }

    public var rows: [Row] { [.account, .dorm, .laundry] }
    /// The rows the count is out of.
    private var needed: [Row] { [.account, .dorm] }

    public func isDone(_ row: Row) -> Bool {
        switch row {
        case .account: signedIn
        case .dorm: dormDone
        case .laundry: laundry != .open
        case .controller: dormDone && controllerBound && controllerChecked
        }
    }

    /// The step page a row opens: the dorm needs the account first.
    public func step(for row: Row) -> Row {
        row == .dorm && !signedIn ? .account : row
    }

    /// After the dorm step: the controller check while the bound controller wasn't checked.
    public var afterDorm: Row? { controllerBound && !controllerChecked ? .controller : nil }

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
        case .laundry: "洗衣机（可选）"
        case .controller: "水控"
        }
    }

    public func detail(_ row: Row) -> String {
        switch row {
        case .account: return signedIn ? "已登录，可查询校园卡余额" : "登录后自动同步校园卡余额"
        case .dorm: return dorm.flatMap { dormDone ? $0.replacingOccurrences(of:" ", with:"") : nil } ?? "选择楼栋房间，确认自己的设备"
        case .laundry:
            switch laundry {
            case .open: return "可以跳过，需要时再登录 U净并扫码添加"
            case .saved(let count): return "已保存 \(count) 台机器"
            case .notUsed: return "不用学校的洗衣机"
            }
        case .controller: return isDone(.controller) ? "已核对" : "核对宿舍的水控"
        }
    }

    /// 「已完成 1 / 2」.
    public var progress: String { "已完成 \(doneCount) / \(needed.count)" }
    public var headline: String { allDone ? "都准备好了" : "完成首次设置" }
    public var hint: String {
        if !signedIn { return "先登录学校账号，再选择宿舍。洗衣机可以稍后添加。" }
        if !dormDone { return "学校账号已登录，接着选择你的宿舍。" }
        return "宿舍已保存，可以开始使用；洗衣机按需添加。"
    }
    /// The button under the rows: on to the next needed row, or done.
    public var button: String {
        if allDone { return isDone(.laundry) ? "完成设置" : "完成设置，暂不绑定洗衣机" }
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
