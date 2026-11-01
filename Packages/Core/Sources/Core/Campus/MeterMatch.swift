import Foundation

public enum MeterMatch: Sendable, Equatable {
    case one(Meter)
    /// Zero rows match.
    case none
    /// Several rows match: nothing tells them apart.
    case many([Meter])
}

public enum MeterMatcher {
    /// Matches a room's `getMeterStatus` rows on `piplineName == "<building>栋<room>"`.
    public static func match(_ rows: [Meter], address: DormAddress) -> MeterMatch {
        let hits = rows.filter { address.matchesMeterName($0.name) }
        switch hits.count {
        case 0: return .none
        case 1: return .one(hits[0])
        default: return .many(hits)
        }
    }

    /// Picks the saved meter from the rows of its node.
    public static func pick(_ rows: [Meter], binding: MeterBinding) -> Meter? {
        if let exact = rows.first(where: { $0.comAddress == binding.comAddress }) { return exact }
        return nil
    }
}
