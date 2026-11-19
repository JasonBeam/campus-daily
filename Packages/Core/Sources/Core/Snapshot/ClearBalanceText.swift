import Foundation

/// Words and numbers of 清爽 home's 双余额 card and the rest of its page: two decimals, 「电费」 and
/// 「昨日」 under the electricity, 「校园消费余额」 under the card, each column with its own read
/// time, and one 「校园充值 · 微信」 link at the bottom.
public enum ClearBalanceText {
    public static let homeTitle = "校园生活"
    public static let title = "双余额"
    public static let powerTitle = "宿舍电量"
    public static let cardTitle = "校园卡"
    public static let cardCaption = "校园消费余额"
    public static let topUp = "校园充值 · 微信"
    public static let pullHint = "下拉刷新余额"
    /// A reading older than this (or with a failed read after it) is drawn as 「上次」.
    public static let staleAfter: TimeInterval = 20 * 60

    /// 「电表设置」 once a meter is bound, 「绑定电表」 before.
    public static func meterLink(bound: Bool) -> String { bound ? "电表设置" : "绑定电表" }

    /// 「3栋108」: the dorm without the spaces of the other pages.
    public static func room(_ dorm: String?) -> String? {
        guard let dorm else { return nil }
        let compact = dorm.replacingOccurrences(of: " ", with: "")
        return compact.isEmpty ? nil : compact
    }

    /// 「42.60」, 「1,234.50」: always two places; 「—」 for nothing read.
    public static func number(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    /// 「电费 ¥25.56」, or 「电费 未获取」 without a meter reading or its money.
    public static func powerMoney(_ meter: Meter?) -> String {
        "电费 " + (meter?.leftMoney.map { "¥" + number($0.yuan) } ?? "未获取")
    }

    /// 「昨日 4.60 度」, or 「昨日 未返回」 when the meter didn't report it.
    public static func yesterday(_ meter: Meter?) -> String {
        "昨日 " + (meter?.dailyUseKWh.map { number($0) + " 度" } ?? "未返回")
    }

    /// Older than `staleAfter`, read after it with an error, or dated in the future.
    public static func isStale<Value: Sendable & Codable & Equatable>(_ tile: Tile<Value>, now: Date) -> Bool {
        guard let at = tile.fetchedAt else { return true }
        return tile.error != nil || now.timeIntervalSince(at) > staleAfter || now < at
    }

    /// The electricity column's time: 「查询 7:01」, 「上次 7:01」 once stale; nil before any read.
    public static func powerStamp(_ tile: Tile<Meter>, now: Date, locale: Locale = .autoupdatingCurrent,
                                  timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        guard let at = tile.fetchedAt else { return nil }
        return (isStale(tile, now: now) ? "上次 " : "查询 ") + clock(at, locale: locale, timeZone: timeZone)
    }

    /// The card column's time: always 「查询 7:01」; nil before any read.
    public static func cardStamp(_ tile: Tile<Money>, locale: Locale = .autoupdatingCurrent,
                                 timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        tile.fetchedAt.map { "查询 " + clock($0, locale: locale, timeZone: timeZone) }
    }

    /// The card column's second small line: 「更新中」, 「已更新」, 「上次余额」, 「暂未获取」 or
    /// 「待配置」 (signed out).
    public static func cardFreshness(_ tile: Tile<Money>, signedIn: Bool, refreshing: Bool, now: Date) -> String {
        if refreshing { return "更新中" }
        if tile.value != nil { return isStale(tile, now: now) ? "上次余额" : "已更新" }
        return signedIn ? "暂未获取" : "待配置"
    }

    /// Failed reads, listed in the card: the card's problem, then 「电费：…」 for the meter's.
    public static func issues(_ snapshot: HomeSnapshot, signedIn: Bool, meterBound: Bool) -> [String] {
        guard signedIn else { return [] }
        var lines: [String] = []
        if let error = snapshot.card.error { lines.append(error.userMessage) }
        if meterBound, let error = snapshot.power.error { lines.append("电费：" + error.userMessage) }
        return lines
    }

    /// 「7:01」 in the reader's own clock style (「早上7:01」 in Chinese).
    public static func clock(_ date: Date, locale: Locale = .autoupdatingCurrent,
                             timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// 「¥1.32」 as the system writes yuan for the reader (「CN¥1.32」 outside China's region).
    public static func currency(_ yuan: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        yuan.formatted(.currency(code: "CNY").locale(locale))
    }

    /// 「2026年11月9日 上午11:02」: when the last shower was settled.
    public static func dateTime(_ date: Date, locale: Locale = .autoupdatingCurrent,
                                timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
