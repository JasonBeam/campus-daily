import Foundation

/// The dorm address the portal registers (`getMyInfo.gydz`), e.g. "示例校区99栋9号1层991房".
/// Format: `<campus>校区 <building>栋|幢 [<unit>号] <floor>层|楼 <room>房|室`.
public struct DormAddress: Sendable, Equatable, Hashable, Codable {
    public let campus: String
    public let building: String
    public let unit: String?
    public let floor: Int
    public let room: String

    public init(campus: String, building: String, unit: String?, floor: Int, room: String) {
        self.campus = campus
        self.building = building
        self.unit = unit
        self.floor = floor
        self.room = room
    }

    private static let pattern = try! NSRegularExpression(
        pattern: "^(.{1,32}校区)([A-Za-z]?[0-9]{1,3})(?:栋|幢)(?:([0-9]{1,3})号)?([0-9]{1,2})(?:层|楼)([0-9]{2,6}[A-Za-z]?)(?:房|室)$")

    /// Parses the portal string; whitespace is ignored. `nil` for anything else
    /// (no guessing from partial addresses).
    public static func parse(_ raw: String) -> DormAddress? {
        let text = raw.filter { !$0.isWhitespace }
        guard !text.isEmpty, text.count <= 128 else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = pattern.firstMatch(in: text, range: range) else { return nil }
        func part(_ i: Int) -> String? {
            Range(m.range(at: i), in: text).map { String(text[$0]) }
        }
        guard let campus = part(1), let building = part(2), let floorText = part(4),
              let floor = Int(floorText), floor > 0, let room = part(5) else { return nil }
        return DormAddress(campus: campus, building: building, unit: part(3), floor: floor, room: room)
    }

    /// The electricity meter's `piplineName` for this room, e.g. "99栋991".
    public var meterName: String { building + "栋" + room }

    /// Display label, e.g. "99栋 991".
    public var roomLabel: String { building + "栋 " + room }

    /// Chinese-numeral floor label used by the hot-water platform: 1 → "一楼", 12 → "十二楼".
    public var chineseFloorLabel: String { DormAddress.chineseNumeral(floor) + "楼" }

    /// All spellings of this floor seen across school systems ("1楼", "1层", "一楼", "一层").
    public var floorLabels: [String] {
        let cn = DormAddress.chineseNumeral(floor)
        return ["\(floor)楼", "\(floor)层", cn + "楼", cn + "层"]
    }

    public static func chineseNumeral(_ n: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard n >= 0, n < 100 else { return String(n) }
        if n < 10 { return digits[n] }
        let tens = n / 10, ones = n % 10
        return (tens == 1 ? "" : digits[tens]) + "十" + (ones == 0 ? "" : digits[ones])
    }

    private static func normalized(_ label: String) -> String {
        label.filter { !$0.isWhitespace && $0 != "·" }
    }

    public func matchesCampus(_ label: String) -> Bool { DormAddress.normalized(label) == campus }

    public func matchesBuilding(_ label: String) -> Bool {
        [building + "栋", building + "幢", building + "号楼"].contains(DormAddress.normalized(label))
    }

    public func matchesFloor(_ label: String) -> Bool {
        floorLabels.contains(DormAddress.normalized(label))
    }

    public func matchesRoom(_ label: String) -> Bool {
        [room, room + "房", room + "室"].contains(DormAddress.normalized(label))
    }

    /// Exact match of an electricity `piplineName` ("99栋991"; "99栋 · 991" tolerated).
    public func matchesMeterName(_ label: String) -> Bool {
        let n = DormAddress.normalized(label)
        return n == meterName || n == meterName + "房" || n == meterName + "室"
    }
}
