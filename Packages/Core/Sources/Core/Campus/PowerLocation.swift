import Foundation

/// Full dorm and meter locations, 「校区 · 公寓 · 楼栋 · 房间」. Same-named
/// buildings exist in different apartments, so the short 「3 栋 108」 alone can't say which.
public enum PowerLocation {
    static let separator = " · "

    public static func joined(_ names: [String]) -> String {
        names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: separator)
    }

    /// Directory names walked in the manual picker; floor levels (「1楼」「三层」) are left out.
    public static func label(_ names: [String]) -> String {
        joined(names.filter { !isFloor($0) })
    }

    /// 「1楼」「12层」「一楼」「十二层」. Not 「3号楼」 (a building).
    static func isFloor(_ name: String) -> Bool {
        let text = name.filter { !$0.isWhitespace }
        guard let last = text.last, last == "楼" || last == "层" else { return false }
        let number = text.dropLast()
        guard !number.isEmpty, number.count <= 3 else { return false }
        return number.allSatisfy { $0.isASCII && $0.isNumber || "零一二三四五六七八九十".contains($0) }
    }

    /// From the portal address alone: 校区 · 楼栋 · 房间 (the portal names no apartment).
    public static func dorm(_ address: DormAddress) -> String {
        joined([address.campus, address.building + "栋", address.room])
    }
}

extension SchoolProfile {
    /// The dorm's full location for Settings. The meter's location is used when it is the same
    /// room, because only the electricity directory knows the apartment; otherwise the
    /// portal address. nil when the portal gave no readable dorm.
    public var dormLocation: String? {
        guard let address = residence?.address else { return nil }
        return directoryDormLocation ?? PowerLocation.dorm(address)
    }

    /// The dorm as the electricity directory names it (校区 · 公寓 · 楼栋 · 房间), when the bound
    /// meter is the portal's room. nil without one: a campus-wide binding only knows the campus.
    public var directoryDormLocation: String? {
        guard let address = residence?.address, let location = meter?.location,
              PowerLocation.sameRoom(location, address) else { return nil }
        return location
    }

    /// The bound meter's full location (bindings from before it was kept show their label).
    public var meterLocation: String? {
        guard let meter else { return nil }
        return meter.location ?? meter.label
    }
}

extension PowerLocation {
    /// The location's campus, building and room are this address's (the apartment may be anything).
    static func sameRoom(_ location: String, _ address: DormAddress) -> Bool {
        let parts = location.components(separatedBy: separator)
        guard parts.count >= 3, let first = parts.first, let last = parts.last else { return false }
        return address.matchesCampus(first) && address.matchesRoom(last)
            && parts.dropFirst().dropLast().contains(where: address.matchesBuilding)
    }
}
