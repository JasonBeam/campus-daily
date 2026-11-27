//
//  SpendStats+Make.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import Foundation

extension SpendSpan {
    /// Where the records page keeps the span last chosen (its raw value).
    public static let storeKey = "records.statsSpan"

    /// Days in the span, today counted; nil for this term (its start day decides).
    public var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .term: return nil
        }
    }
}

extension SpendStats {
    /// The oldest day (`yyyyMMdd`) the records must be read back to for `span`: the span and the
    /// period before it (14 / 60 days), or this term's start day.
    public static func firstDayNeeded(span: SpendSpan, today: Date, termStart: Date,
                                      calendar: Calendar = SchoolCalendar.shanghai) -> String {
        let now = calendar.startOfDay(for: today)
        guard let days = span.days else {
            return SchoolCalendar.dayString(min(calendar.startOfDay(for: termStart), now), calendar: calendar)
        }
        return SchoolCalendar.dayString(calendar.date(byAdding: .day, value: -(2 * days - 1), to: now) ?? now, calendar: calendar)
    }

    /// The stats of `span` from the records `history` has read, on its today. Payments only, by
    /// the rule of each day's total in the list (`CardSpend`): money in (top-ups, refunds,
    /// WeChat's half of a meal) never counts, a payment under a top-up's name counts as 其他, and
    /// a meal paid with WeChat counts once, as `history.records` merges it. Nil while a day of
    /// the span is not read yet.
    ///
    /// A day is unsure when its records may be incomplete or repeated (`CardHistory.isComplete`), or
    /// one of its records may be money in or out (left out). When the list has reached its end
    /// and the school's oldest record is after the span's first day, the stats begin on that
    /// record's day (`coveredFrom`) and the average is over the days from it.
    ///
    /// Only the categories in `included` count: the total, the average, the comparison and the
    /// bars leave the others out, and so does a day's doubt about a record of theirs. `shares`
    /// still lists every category left out, with what was spent on it; when only those were spent
    /// on, the ones counted are listed too, at nothing spent.
    public static func make(span: SpendSpan, history: CardHistory, termStart: Date,
                            included: Set<CardRecordKind> = Set(SpendCategories.all),
                            calendar: Calendar = SchoolCalendar.shanghai,
                            now: Date? = nil) -> SpendStats? {
        let today = history.today
        let wallToday = calendar.startOfDay(for: now ?? today)
        let isCurrentDay = calendar.isDate(today, inSameDayAs: wallToday)
        let first: Date
        if let days = span.days {
            first = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        } else {
            first = min(calendar.startOfDay(for: termStart), today)
        }
        let spanDays = dayList(from: first, to: today, calendar: calendar)
        guard let firstID = spanDays.first?.id, history.hasRead(through: firstID) else { return nil }

        let records = history.records
        var spentOn: [String: Int] = [:], byKind: [CardRecordKind: Int] = [:], doubtful = Set<String>()
        var oldest: String?
        for record in records {
            let day = CardHistory.trimmed(record.date)
            let readableDay = day.count == 8 && day.allSatisfy { $0.isASCII && $0.isNumber }
            if readableDay { oldest = min(oldest ?? day, day) }
            // Paid from the card under a top-up's name (「网费充值」, 「xx圈存」): spent on
            // something else.
            let named = CardRecordKind.of(record)
            let kind: CardRecordKind = named == .topUp ? .other : named
            switch CardSpend.of(record, calendar: calendar) {
            case .moneyIn: continue
            case .unsure(let unsureDay):
                // Its day, when readable, can't be summed for sure, unless it would not count.
                if let unsureDay, included.contains(kind) { doubtful.insert(unsureDay) }
            case .paid(_, let amount):
                if day >= firstID && day <= spanDays.last!.id { byKind[kind, default: 0] += amount.fen }
                if included.contains(kind) { spentOn[day, default: 0] += amount.fen }
            }
        }

        let coveredFrom = history.reachedEnd ? oldest.flatMap { $0 > firstID ? $0 : nil } : nil
        func unsure(_ day: String) -> Bool {
            if let coveredFrom, day < coveredFrom { return false }
            return doubtful.contains(day) || !history.isComplete(day: day)
        }
        let covered = spanDays.filter { day in coveredFrom.map { day.id >= $0 } ?? true }
        let total = covered.reduce(0) { $0 + (spentOn[$1.id] ?? 0) }

        var versusPrevious: Money?
        if let days = span.days, coveredFrom == nil,
           let previousFirst = calendar.date(byAdding: .day, value: -(2 * days - 1), to: today),
           let previousLast = calendar.date(byAdding: .day, value: -days, to: today) {
            let previous = dayList(from: previousFirst, to: previousLast, calendar: calendar).map(\.id)
            // The list ended inside the period (or before it had a record): the school may hold
            // no older records rather than none spent.
            let stopsInside = history.reachedEnd && (oldest.map { $0 > previous[0] } ?? true)
            if !stopsInside, previous.allSatisfy({ history.isComplete(day: $0) && !doubtful.contains($0) }) {
                versusPrevious = Money(fen: total - previous.reduce(0) { $0 + (spentOn[$1] ?? 0) })
            }
        }

        let todayID = SchoolCalendar.dayString(today, calendar: calendar)
        var bars: [SpendBar]
        if span.days != nil {
            bars = spanDays.enumerated().map { i, day in
                SpendBar(id: day.id, days: [day.id], spent: Money(fen: spentOn[day.id] ?? 0), unsure: unsure(day.id),
                         isCurrent: isCurrentDay && day.id == todayID, beforeStart: false,
                         axisLabel: dayLabel(span: span, index: i, count: spanDays.count, day: day.date, calendar: calendar))
            }
        } else {
            bars = weekBars(spanDays, spentOn: spentOn, unsure: unsure, isCurrentDay: isCurrentDay, calendar: calendar)
        }
        if !bars.isEmpty {
            if isCurrentDay {
                bars[bars.count - 1].axisLabel = span == .term ? "本周" : "今天"
            } else if span == .month {
                bars[bars.count - 1].axisLabel = SchoolCalendar.dayTitle(today, calendar: calendar)
            } else if span == .term, bars[bars.count - 1].axisLabel == nil {
                bars[bars.count - 1].axisLabel = SchoolCalendar.dayTitle(today, calendar: calendar)
            }
        }

        // Left out, it stays on the list at nothing spent: it can be counted again from there.
        for kind in SpendCategories.all where !included.contains(kind) && byKind[kind] == nil { byKind[kind] = 0 }
        // Spent only on categories left out: those counted are listed at nothing spent too, so
        // it shows which are on. Otherwise a category counted with nothing spent is not listed.
        let onlyLeftOut = total == 0 && byKind.contains { !included.contains($0.key) && $0.value > 0 }
        if onlyLeftOut {
            for kind in SpendCategories.all where included.contains(kind) && byKind[kind] == nil { byKind[kind] = 0 }
        }
        let shares = byKind.filter { $0.value > 0 || !included.contains($0.key) || onlyLeftOut }
            .sorted { a, b in
                if (a.key == .other) != (b.key == .other) { return b.key == .other }
                if a.value != b.value { return a.value > b.value }
                return order(a.key) < order(b.key)
            }
            .map { share in
                let counted = included.contains(share.key)
                return SpendShare(kind: share.key, spent: Money(fen: share.value),
                                  fraction: counted && total > 0 ? Double(share.value) / Double(total) : 0, included: counted)
            }

        return SpendStats(span: span, total: Money(fen: total),
                          dailyAverage: Money(fen: dividedRounding(total, by: max(covered.count, 1))),
                          versusPrevious: versusPrevious, bars: bars, shares: shares,
                          unsureDays: covered.filter { unsure($0.id) }.count, coveredFrom: coveredFrom,
                          termStart: span == .term ? firstID : nil)
    }

    private struct Day { var id: String; var date: Date }

    private static func dayList(from first: Date, to last: Date, calendar: Calendar) -> [Day] {
        var days: [Day] = [], day = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        while day <= end {
            days.append(Day(id: SchoolCalendar.dayString(day, calendar: calendar), date: day))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// 7 days: each weekday (「一」…「日」); 30 days: the first and the middle day (「10月25日」).
    /// The last bar's (「今天」) is set by the caller.
    private static func dayLabel(span: SpendSpan, index: Int, count: Int, day: Date, calendar: Calendar) -> String? {
        if span == .week {
            return ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: day) - 1]
        }
        return index == 0 || index == count / 2 ? SchoolCalendar.dayTitle(day, calendar: calendar) : nil
    }

    /// One bar per Monday-to-Sunday week from the week holding the term's first day, each with the
    /// term's days in it through today. A week's label is its month (「9月」) when its first day
    /// begins a new month on the chart; the last bar's (「本周」) is set by the caller.
    private static func weekBars(_ days: [Day], spentOn: [String: Int], unsure: (String) -> Bool,
                                 isCurrentDay: Bool, calendar: Calendar) -> [SpendBar] {
        var weeks: [[Day]] = []
        for day in days {
            // Weekday 2 is Monday.
            if weeks.isEmpty || calendar.component(.weekday, from: day.date) == 2 { weeks.append([day]) } else { weeks[weeks.count - 1].append(day) }
        }
        var lastMonth: Int?
        return weeks.map { week in
            let month = calendar.component(.month, from: week[0].date)
            let label = month == lastMonth ? nil : "\(month)月"
            lastMonth = month
            let ids = week.map(\.id)
            return SpendBar(id: ids[0], days: ids, spent: Money(fen: ids.reduce(0) { $0 + (spentOn[$1] ?? 0) }),
                            unsure: ids.contains(where: unsure), isCurrent: isCurrentDay && week.last?.id == days.last?.id,
                            beforeStart: false, axisLabel: label)
        }
    }

    private static func order(_ kind: CardRecordKind) -> Int { CardRecordKind.allCases.firstIndex(of: kind) ?? 0 }

    /// `fen ÷ days` to the nearest fen, halves away from zero.
    static func dividedRounding(_ fen: Int, by days: Int) -> Int {
        let q = (2 * abs(fen) + days) / (2 * days)
        return fen < 0 ? -q : q
    }
}
