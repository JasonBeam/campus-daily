//
//  SpendStats.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import Foundation

/// The span the records page's spending stats cover: 7 days, 30 days (both counting today)
/// or this term (from its start day through today).
public enum SpendSpan: String, Sendable, Codable, CaseIterable {
    case week, month, term
}

/// One bar of the stats chart: a day (7 / 30 days) or a week (this term), oldest first.
public struct SpendBar: Sendable, Equatable, Identifiable {
    /// First day of the bar, `yyyyMMdd`.
    public var id: String
    /// Days the bar covers, `yyyyMMdd`, oldest first (one for a day bar).
    public var days: [String]
    /// Money spent on the card in the bar; zero when nothing was spent.
    public var spent: Money
    /// Some of its days may miss records or show one twice: its amount may be off.
    public var unsure: Bool
    /// Today, or this term's current week: not over yet.
    public var isCurrent: Bool
    /// Before the term's start day (a term's first week can begin before it): not selectable.
    public var beforeStart: Bool
    /// Axis label under the bar, or nil for none (7 days: 「二」…「今天」; 30 days: first,
    /// middle and last date; term: the month at a month's first week, 「本周」 last).
    public var axisLabel: String?

    public init(id: String, days: [String], spent: Money, unsure: Bool, isCurrent: Bool,
                beforeStart: Bool, axisLabel: String?) {
        self.id = id; self.days = days; self.spent = spent; self.unsure = unsure
        self.isCurrent = isCurrent; self.beforeStart = beforeStart; self.axisLabel = axisLabel
    }
}

/// Spending in one category over the span; only kinds with money spent, biggest first,
/// 「其他」 always last; top-ups never.
public struct SpendShare: Sendable, Equatable, Identifiable {
    public var kind: CardRecordKind
    public var spent: Money
    /// Share of the total, 0...1.
    public var fraction: Double
    public var id: CardRecordKind { kind }

    public init(kind: CardRecordKind, spent: Money, fraction: Double) {
        self.kind = kind; self.spent = spent; self.fraction = fraction
    }
}

/// The records page's spending stats for one span, worked out from the card records read.
public struct SpendStats: Sendable, Equatable {
    public var span: SpendSpan
    /// Total spent on the card in the span (records read so far; see `coveredFrom`).
    public var total: Money
    /// Total ÷ the days covered (today counted).
    public var dailyAverage: Money
    /// Total minus the period just before it of the same length; nil for this term, or when
    /// that period was not read in full (or holds an unsure day).
    public var versusPrevious: Money?
    public var bars: [SpendBar]
    public var shares: [SpendShare]
    /// Days in the span whose records may be incomplete or repeated.
    public var unsureDays: Int
    /// The school's records stop before the span's first day: the stats begin here
    /// (`yyyyMMdd`). Nil when the span is fully covered.
    public var coveredFrom: String?
    /// This term's start day (`yyyyMMdd`); nil for 7 / 30 days.
    public var termStart: String?

    public init(span: SpendSpan, total: Money, dailyAverage: Money, versusPrevious: Money?,
                bars: [SpendBar], shares: [SpendShare], unsureDays: Int, coveredFrom: String?,
                termStart: String?) {
        self.span = span; self.total = total; self.dailyAverage = dailyAverage
        self.versusPrevious = versusPrevious; self.bars = bars; self.shares = shares
        self.unsureDays = unsureDays; self.coveredFrom = coveredFrom; self.termStart = termStart
    }

    /// Nothing spent in the span.
    public var isEmpty: Bool { total == .zero }
}
