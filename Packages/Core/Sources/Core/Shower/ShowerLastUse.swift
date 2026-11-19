import Foundation

/// 「最近一次用水」 on 清爽's 热水 page: the last settled shower, from what home's 热水 tile shows
/// as 「上次 11 分钟 · ¥1.32」, so the page has the card exactly when the tile has those words.
public struct ShowerLastUse: Equatable, Sendable {
    public var minutes: Int
    public var cost: Decimal?
    /// When it was settled, if kept.
    public var ended: Date?

    public init(minutes: Int, cost: Decimal?, ended: Date?) {
        self.minutes = minutes; self.cost = cost; self.ended = ended
    }

    /// Nil without the minutes, as the tile then says nothing of the last shower.
    public static func of(minutes: Int?, cost: Decimal?, ended: Date?) -> ShowerLastUse? {
        guard let minutes else { return nil }
        return ShowerLastUse(minutes: minutes, cost: cost, ended: ended)
    }

    /// 「11 分钟」, the tile's words.
    public var duration: String { "\(minutes) 分钟" }
    /// 「¥1.32」; nil when no amount was read.
    public var amount: String? { cost.map { Money(yuan: $0).description } }
}
