//
//  TermStart.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import Foundation

/// 「本学期」's first day. The school gives no calendar: spring terms count from 3月1日 and autumn
/// terms from 9月1日 (January and February belong to the autumn term), unless the user set the
/// day themselves (开学日). A day they set counts for its own term only: once today reaches the
/// next default term, the default is back.
public enum TermStart {
    /// A set day this close before a default start (a spring term opening in late February, an
    /// autumn one in August) belongs to the term that default starts.
    public static let earlyDays = 28

    /// 3月1日 this year from March to August; otherwise 9月1日 (last year's in January and February).
    public static func defaultStart(today: Date, calendar: Calendar = SchoolCalendar.shanghai) -> Date {
        let p = calendar.dateComponents([.year, .month], from: today)
        let year = p.year ?? 2000, month = p.month ?? 1
        let start: DateComponents
        switch month {
        case 3...8: start = DateComponents(year: year, month: 3, day: 1)
        case 9...12: start = DateComponents(year: year, month: 9, day: 1)
        default: start = DateComponents(year: year - 1, month: 9, day: 1)
        }
        return calendar.date(from: start) ?? calendar.startOfDay(for: today)
    }

    /// The default start of the term `day` belongs to as a set start day (see `earlyDays`).
    static func term(of day: Date, calendar: Calendar) -> Date {
        let shifted = calendar.date(byAdding: .day, value: earlyDays, to: calendar.startOfDay(for: day)) ?? day
        return defaultStart(today: shifted, calendar: calendar)
    }

    /// `custom` still counts today: it is not after today, and today has not reached the default
    /// term after its own.
    public static func isActive(custom: Date, today: Date, calendar: Calendar = SchoolCalendar.shanghai) -> Bool {
        let day = calendar.startOfDay(for: custom), now = calendar.startOfDay(for: today)
        guard day <= now else { return false }
        let own = term(of: day, calendar: calendar)
        guard let next = calendar.date(byAdding: .month, value: 6, to: own) else { return false }
        return now < next
    }

    /// The start day in effect today: `custom` while it counts, otherwise the default.
    public static func start(today: Date, custom: Date?, calendar: Calendar = SchoolCalendar.shanghai) -> Date {
        if let custom, isActive(custom: custom, today: today, calendar: calendar) { return calendar.startOfDay(for: custom) }
        return defaultStart(today: today, calendar: calendar)
    }

    /// Days the start can be set to: the earliest day the current term takes (`earlyDays` before
    /// its default start) through today. Every one of them counts today (`isActive`).
    public static func pickerRange(today: Date, calendar: Calendar = SchoolCalendar.shanghai) -> ClosedRange<Date> {
        let now = calendar.startOfDay(for: today)
        let start = defaultStart(today: today, calendar: calendar)
        let first = calendar.date(byAdding: .day, value: -earlyDays, to: start) ?? start
        return min(first, now)...now
    }
}

/// The start day the user set (开学日), kept in the app's preferences as `yyyyMMdd`.
public struct TermStartStore {
    public static let key = "records.termStart"
    private let preferences: any PreferenceStorage
    private let calendar: Calendar

    public init(preferences: any PreferenceStorage, calendar: Calendar = SchoolCalendar.shanghai) {
        self.preferences = preferences; self.calendar = calendar
    }

    /// The day set, whether or not it still counts (`TermStart.start`); nil when none or unreadable.
    public var custom: Date? {
        guard let text = preferences.object(forKey: Self.key) as? String, text.count == 8,
              text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let year = Int(text.prefix(4)), let month = Int(text.dropFirst(4).prefix(2)), let day = Int(text.suffix(2)),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              SchoolCalendar.dayString(date, calendar: calendar) == text else { return nil }
        return date
    }

    public func set(_ day: Date) {
        preferences.set(SchoolCalendar.dayString(day, calendar: calendar), forKey: Self.key)
    }

    public func clear() { preferences.set(nil, forKey: Self.key) }
}
