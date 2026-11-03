import Foundation

/// 清爽's 首次设置 checklist: which rows it shows, which are done or wait for the row before,
/// how many are done, which row its button continues with, and what each row says.
///
/// Rows in order: 学校账号, 宿舍 (after the account), 学校洗衣机, 水控 (after the dorm; gone once
/// the dorm is confirmed without a controller, as there is nothing to check). 「不用」 answers
/// the laundry row.
public struct SetupChecklist: Equatable, Sendable {
    public enum Row: Hashable, CaseIterable, Sendable {
        case account, dorm, laundry, controller
    }

    public enum Laundry: Equatable, Sendable {
        /// Not answered: on, with no machine saved yet.
        case open
        /// A machine saved (「3 号机」).
        case machine(String)
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

    public var rows: [Row] {
        Row.allCases.filter { $0 != .controller || !dormDone || controllerBound }
    }

    public func isDone(_ row: Row) -> Bool {
        switch row {
        case .account: signedIn
        case .dorm: dormDone
        case .laundry: laundry != .open
        case .controller: dormDone && controllerBound && controllerChecked
        }
    }

    /// Waits for the row before it (the dorm for the account, the controller for the dorm).
    public func isBlocked(_ row: Row) -> Bool {
        switch row {
        case .account, .laundry: false
        case .dorm: !signedIn
        case .controller: !dormDone
        }
    }

    public var doneCount: Int { rows.filter(isDone).count }
    /// The first row not done; nil when all are.
    public var next: Row? { rows.first { !isDone($0) } }
    public var allDone: Bool { next == nil }
    /// For the progress bar, 0...1.
    public var fraction: Double { rows.isEmpty ? 1 : Double(doneCount) / Double(rows.count) }

    // MARK: Copy (campus-clear-v2-copy.md 首次设置清单)

    public static let later = "以后再说"
    public static let footnote = "这里只读取和保存设置，不会开水、下单或付款。"
    public static let start = "开始用"

    public static func title(_ row: Row) -> String {
        switch row {
        case .account: "学校账号"
        case .dorm: "宿舍"
        case .laundry: "学校洗衣机"
        case .controller: "水控"
        }
    }

    public func detail(_ row: Row) -> String {
        if isBlocked(row) { return row == .dorm ? "先设好学校账号" : "先选好宿舍" }
        switch row {
        case .account: return signedIn ? "已登录" : "登录后读校园卡和宿舍"
        case .dorm: return dorm.flatMap { dormDone ? $0 : nil } ?? "确认你住哪间"
        case .laundry:
            switch laundry {
            case .open: return "用不用学校的洗衣机"
            case .machine(let name): return name
            case .notUsed: return "不用"
            }
        case .controller: return isDone(.controller) ? "已核对" : "核对宿舍的水控"
        }
    }

    /// 「已完成 2 / 4」.
    public var progress: String { "已完成 \(doneCount) / \(rows.count)" }
    public var headline: String { allDone ? "都设好了" : "先把这几项设好" }
    public var hint: String { allDone ? "以后都能在设置里改。" : "设好以后，首页就能看电量和余额，也能洗澡。" }
    /// 「继续 · 宿舍」, or 「开始用」 when all are done.
    public var button: String { next.map { "继续 · " + Self.title($0) } ?? Self.start }

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
