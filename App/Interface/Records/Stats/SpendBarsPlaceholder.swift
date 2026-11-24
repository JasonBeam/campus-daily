//
//  SpendBarsPlaceholder.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import Foundation
import Core

/// The bars a span will have, without amounts: drawn in `fill` while the stats are read, so the
/// chart has its final shape and labels from the start.
enum SpendBarsPlaceholder {
    /// 7 / 30 days through today, or a bar a week from `termStart`'s week; labelled as the
    /// stats' bars are (「二」…「今天」; first, middle and last date; months, then 「本周」).
    static func bars(_ span: SpendSpan, termStart: Date, now: Date = Date(),
                     calendar: Calendar = SchoolCalendar.shanghai) -> [SpendBar] {
        let today = calendar.startOfDay(for:now)
        func id(_ date: Date) -> String { SchoolCalendar.dayString(date, calendar:calendar) }
        switch span {
        case .week, .month:
            let count = span == .week ? 7 : 30
            return (0..<count).map { index in
                let date = calendar.date(byAdding:.day, value:index - (count - 1), to:today) ?? today
                let last = index == count - 1
                let label: String? = if last {
                    "今天"
                } else if span == .week {
                    String(SchoolCalendar.weekday(date, calendar:calendar).dropFirst())
                } else if index == 0 || index == count / 2 {
                    SchoolCalendar.dayTitle(date, calendar:calendar)
                } else { nil }
                return SpendBar(id:id(date), days:[id(date)], spent:.zero, unsure:false, isCurrent:last,
                                beforeStart:false, axisLabel:label)
            }
        case .term:
            var bars: [SpendBar] = []
            var weekStart = min(calendar.startOfDay(for:termStart), today)
            var lastMonth = 0
            while weekStart <= today, bars.count < 60 {
                let toSunday = (8 - calendar.component(.weekday, from:weekStart)) % 7
                let weekEnd = min(calendar.date(byAdding:.day, value:toSunday, to:weekStart) ?? today, today)
                var days: [String] = []
                var cursor = weekStart
                while cursor <= weekEnd, let next = calendar.date(byAdding:.day, value:1, to:cursor) {
                    days.append(id(cursor))
                    cursor = next
                }
                let month = calendar.component(.month, from:weekStart)
                let current = weekEnd >= today
                bars.append(SpendBar(id:days.first ?? id(weekStart), days:days, spent:.zero, unsure:false,
                                     isCurrent:current, beforeStart:false,
                                     axisLabel:current ? "本周" : (month != lastMonth ? "\(month)月" : nil)))
                lastMonth = month
                guard let next = calendar.date(byAdding:.day, value:1, to:weekEnd) else { break }
                weekStart = next
            }
            return bars
        }
    }
}
