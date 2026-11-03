import Foundation

public enum MeterMatch: Sendable, Equatable {
    case one(Meter)
    /// Zero rows match.
    case none
    /// Several rows match: nothing tells them apart.
    case many
}

public enum MeterMatcher {
    /// Matches a room's `getMeterStatus` rows on `piplineName == "<building>栋<room>"`.
    public static func match(_ rows: [Meter], address: DormAddress) -> MeterMatch {
        let hits = rows.filter { address.matchesMeterName($0.name) }
        switch hits.count {
        case 0: return .none
        case 1: return .one(hits[0])
        default: return .many
        }
    }

    /// Picks the saved meter from the rows of its node. The school replaces a meter under the
    /// same room node with a new `comAddress`: when the node now has one row and it carries the
    /// room's name, that row is the room's meter (the caller moves the binding to it). Any other
    /// mismatch reads as no meter.
    public static func pick(_ rows: [Meter], binding: MeterBinding) -> Meter? {
        if let exact = rows.first(where: { $0.comAddress == binding.comAddress }) { return exact }
        guard rows.count == 1, sameRoom(rows[0].name, binding.label) else { return nil }
        return rows[0]
    }

    /// "99栋991", "99栋 991" and "99栋991房" name the same room.
    static func sameRoom(_ a: String, _ b: String) -> Bool {
        func normalized(_ s: String) -> String {
            var n = s.filter { !$0.isWhitespace && $0 != "·" }
            if n.hasSuffix("房") || n.hasSuffix("室") { n.removeLast() }
            return n
        }
        let n = normalized(a)
        return !n.isEmpty && n == normalized(b)
    }
}
