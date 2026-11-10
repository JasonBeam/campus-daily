import Foundation

/// Words on the meter page (home 电量 › 电表, Settings). Only there: the same failures read as
/// `ServiceError.userMessage` everywhere else.
public enum MeterPageText {
    public static let title = "电表"
    /// Above the picker, before anything is chosen.
    public static let pickerPrompt = "找不到的话，自己选一下"
    /// The school took too long (the lookup or a picker read).
    public static let tooSlow = "学校那边太慢了，等一下再找。"

    /// The page's wording for an issue that reads `ServiceError.userMessage` elsewhere.
    public static func issue(_ text: String) -> String {
        text == ServiceError.timedOut.userMessage ? tooSlow : text
    }

    /// A picker read that failed: a `ServiceError` in the page's words, anything else `otherwise`.
    public static func issue(_ error: Error, otherwise: String) -> String {
        (error as? ServiceError).map { issue($0.userMessage) } ?? otherwise
    }
}

/// One row of a level's list on the meter page.
public struct MeterPickerRow: Sendable, Equatable, Identifiable {
    public var node: PowerNode
    /// 「可能是这个」 under it: the row that matches the dorm.
    public var suggested: Bool
    public var id: String { node.id }
    public init(node: PowerNode, suggested: Bool) { self.node = node; self.suggested = suggested }
}

extension MeterPageText {
    /// The lookup stopped at a level to choose from (home, onboarding, Settings).
    public static let stoppedIssue = "没自动找到电表，去「电表」里选一下。"

    /// What the meter page says above a stopped level's list: only a failure, with
    /// 「再找一次电表」. Nothing while a lookup runs again (its spinner sits by the list header),
    /// nor for the stop itself (the list is the answer).
    public static func noteAtStop(finding: Bool, issue: String?) -> String? {
        guard !finding, let issue, issue != stoppedIssue else { return nil }
        return self.issue(issue)
    }

    /// The question over a stop's candidates, 「2 个公寓都有 3 栋 108，你住哪个？」 (校区 when the
    /// split is at the campuses). nil without candidates or halted branches, or without the dorm.
    /// With branches halted before their rooms among the rows: 「3 栋 108 在哪个公寓？」.
    public static func question(_ stop: MeterWalkStop, address: DormAddress?) -> String? {
        guard let address, !stop.candidates.isEmpty || !stop.halted.isEmpty else { return nil }
        let unit = stop.level == .campus ? "校区" : "公寓"
        guard stop.halted.isEmpty else { return "\(address.building) 栋 \(address.room) 在哪个\(unit)？" }
        var seen: [String] = []
        for c in stop.candidates { if let id = stop.branch(of: c)?.id, !seen.contains(id) { seen.append(id) } }
        return "\(seen.count) 个\(unit)都有 \(address.building) 栋 \(address.room)，你住哪个？"
    }

    /// Under a branch halted before its rooms: tapped, the picker opens where it halted.
    public static let haltedRow = "这边没对上，点进去自己选"

    /// Several apartments (or campuses) to tell apart and one could not be read.
    public static func unfinished(_ level: MeterLevel) -> String {
        "有个\(level == .campus ? "校区" : "公寓")没读完，还分不出是哪间。"
    }

    /// The meter page's search field.
    public static let searchPrompt = "搜索楼栋或房间"
    /// While the lookup runs, on the meter page.
    public static let finding = "正在找电表…"
    /// Under the row that matches the dorm.
    public static let suggestion = "可能是这个"
    /// Right of the matched levels: back to the first level.
    public static let rechoose = "重选"

    /// The header over a level's list. 「选楼层」 has no wording of its own yet: it follows the others.
    public static func header(_ level: MeterLevel) -> String {
        switch level {
        case .campus: return "选校区"
        case .apartment: return "选公寓"
        case .building: return "选楼栋"
        case .floor: return "选楼层"
        case .room: return "选房间"
        }
    }

    /// The levels already chosen, e.g. 「星湖校区 · 半山公寓 · 99栋」 (floors left out).
    public static func matchedLine(_ path: [PowerNode]) -> String {
        PowerLocation.label(path.map(\.name))
    }

    /// The list with the suggested rows first, each order kept.
    public static func rows(_ options: [PowerNode], suggested: [String]) -> [MeterPickerRow] {
        let wanted = Set(suggested)
        let first = options.filter { wanted.contains($0.id) }.map { MeterPickerRow(node: $0, suggested: true) }
        return first + options.filter { !wanted.contains($0.id) }.map { MeterPickerRow(node: $0, suggested: false) }
    }

    /// The rows of `level` that match the dorm (none for apartments: the portal names none).
    public static func suggested(_ options: [PowerNode], at level: MeterLevel, for address: DormAddress?) -> [String] {
        guard let address else { return [] }
        let matches: (String) -> Bool
        switch level {
        case .campus: matches = address.matchesCampus
        case .apartment: return []
        case .building: matches = address.matchesBuilding
        case .floor: matches = address.matchesFloor
        case .room: matches = address.matchesRoom
        }
        return options.filter { matches($0.name) }.map(\.id)
    }
}

extension MeterLevel {
    /// The level of a list read below `current` (nil = the campuses), told from its rows where
    /// the directory may skip one (no apartments, no floors).
    public static func next(after current: MeterLevel?, options: [PowerNode]) -> MeterLevel {
        let names = options.map(\.name)
        let allFloors = !names.isEmpty && names.allSatisfy(PowerLocation.isFloor)
        let anyBuilding = names.contains(where: isBuilding)
        switch current {
        case nil: return .campus
        case .campus?: return anyBuilding ? .building : .apartment
        case .apartment?: return .building
        case .building?: return allFloors ? .floor : .room
        case .floor?, .room?: return .room
        }
    }

    /// 「99栋」「99幢」「3号楼」.
    static func isBuilding(_ name: String) -> Bool {
        let text = name.filter { !$0.isWhitespace }
        return text.hasSuffix("栋") || text.hasSuffix("幢") || text.hasSuffix("号楼")
    }
}
