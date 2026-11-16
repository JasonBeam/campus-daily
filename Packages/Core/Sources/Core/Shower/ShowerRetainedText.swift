import Foundation

/// The words for the kept showers (`ShowerRetainedSummary`) in each theme: the one line that
/// leads to them, the list's title and footnote, and each record's reason. The one place these
/// strings are written.
public enum ShowerRetainedText {
    /// 清爽: the line on the 热水 page and the 订单 tab's section.
    public enum Clear {
        public static func line(count: Int) -> String { "已保留 \(count) 笔费用待核对记录。可在学校官方热水消费明细中核对。" }
        public static func spoken(count: Int) -> String { "已保留 \(count) 笔费用待核对记录，轻点两下查看" }
        public static let sectionTitle = "待核对的热水记录"
        public static let footer = "可在学校官方热水消费明细中核对。"
        public static func reason(_ reason: ShowerRetainedSummary.Reason) -> String {
            switch reason {
            case .stopped: return "停水未结算"
            case .closeUnconfirmed: return "关水未确认"
            case .settleUnconfirmed: return "结算未确认"
            // Provisional: the agreed copy names three reasons and not this one.
            case .authorizeUnclear: return "授权未确认"
            }
        }
    }

    /// 暖橙: the line on 热水洗澡 and its list page.
    public enum Warm {
        public static func line(count: Int) -> String { "有 \(count) 次洗澡没在 App 里结算，点开看看" }
        public static let listTitle = "没结算的洗澡"
        public static let footer = "这些记录只留给你核对，App 不会再为它们扣钱。去学校的热水记录里对一下。"
        public static func reason(_ reason: ShowerRetainedSummary.Reason) -> String {
            switch reason {
            case .stopped: return "在水控上按停的"
            case .closeUnconfirmed: return "结束没确认"
            case .settleUnconfirmed: return "结算没确认"
            // Provisional: the agreed copy names three reasons and not this one.
            case .authorizeUnclear: return "开水没确认"
            }
        }
    }

    /// 「开始时间 · 机器 · 原因」; without a start time (the water never ran) the time is left out.
    public static func row(_ entry: ShowerRetainedSummary.Entry, reason: String, time: (Date) -> String) -> String {
        [entry.started.map(time), entry.machine, reason].compactMap { $0 }.joined(separator: " · ")
    }
}
