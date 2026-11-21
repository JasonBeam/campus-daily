//
//  ShowerRetainedText.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import Foundation

/// The words for the kept showers (`ShowerRetainedSummary`) in each theme: the one line that
/// leads to them, the list's title and footnote, and each record's reason. The one place these
/// strings are written.
public enum ShowerRetainedText {
    /// 清爽: the line on the 热水 page and the 订单 tab's section.
    public enum Clear {
        public static func line(count: Int) -> String { "已保留 \(count) 笔费用待核对记录。可在校园卡消费明细中核对，扣费约 1 小时后入账。" }
        public static func spoken(count: Int) -> String { "已保留 \(count) 笔费用待核对记录，轻点两下查看" }
        public static let sectionTitle = "待核对的热水记录"
        public static let footer = "可在校园卡消费明细中核对，扣费约 1 小时后入账。"
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
        public static let footer = "这些记录只留给你核对，App 不会再为它们扣钱。去校园卡记录里对一下，扣费要 1 小时左右才出现。"
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

    /// 「校园卡已扣 ¥1.32」: a kept or stopped shower the campus card's records show charged
    /// (`ShowerCardCharge`), in both themes. Nothing is said when none matched.
    public static func charged(_ amount: Money) -> String { "校园卡已扣 ¥" + amount.yuanText }
    /// What VoiceOver reads for it.
    public static func chargedSpoken(_ amount: Money) -> String { "校园卡已扣 \(amount.yuanText) 元" }

    /// One kept shower on a list: the start time (or, without one, the reason), then
    /// 「水控 编号 · 原因」, the controller left out when it is the dorm's own (and the line left out
    /// when nothing is left for it), then the card's charge when one matched. Read by VoiceOver
    /// as one sentence.
    public struct Line: Equatable, Sendable {
        public let title: String
        public let detail: String?
        /// 「校园卡已扣 ¥1.32」, or nil.
        public let charge: String?
        let chargeSpoken: String?

        public init(title: String, detail: String?, charge: Money? = nil) {
            self.title = title; self.detail = detail
            self.charge = charge.map(ShowerRetainedText.charged)
            self.chargeSpoken = charge.map(ShowerRetainedText.chargedSpoken)
        }

        public var spoken: String { [title, detail, chargeSpoken].compactMap { $0 }.joined(separator: "，") }
    }

    /// 「水控 AABBCCDD」: a controller other than the dorm's own.
    public static func machine(_ id: String) -> String { "水控 " + id }

    /// The kept showers newest first; those without a start time after the rest, as kept.
    /// `charge`: the card's charge for a shower started then, if one matched.
    public static func lines(_ summary: ShowerRetainedSummary, reason: (ShowerRetainedSummary.Reason) -> String,
                             time: (Date) -> String = { ShowerRetainedText.time($0) },
                             charge: (Date) -> Money? = { _ in nil }) -> [Line] {
        let dated = summary.entries.enumerated().filter { $0.element.started != nil }
            .sorted { ($0.element.started!, $1.offset) > ($1.element.started!, $0.offset) }.map(\.element)
        let undated = summary.entries.filter { $0.started == nil }
        return (dated + undated).map { entry in
            let why = reason(entry.reason)
            let other = entry.machine.flatMap { $0.uppercased() == summary.currentMachine ? nil : machine($0) }
            guard let started = entry.started else { return Line(title: why, detail: other) }
            return Line(title: time(started), detail: [other, why].compactMap { $0 }.joined(separator: " · "),
                        charge: charge(started))
        }
    }

    /// 「11月16日 21:05」.
    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return "\(c.month ?? 0)月\(c.day ?? 0)日 " + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
