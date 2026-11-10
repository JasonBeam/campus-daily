import Foundation

/// How the time of the last good update is written, so a reading from yesterday or earlier
/// never looks like today's. Pure text; the widget and the home screen pass their calendar.
public enum UpdateTimeText {
    /// 「8:10」
    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 「22:10」 today, 「昨天 22:10」 yesterday, 「10月29日 22:10」 earlier (and for a time
    /// after `now`, which only a clock change makes).
    public static func stamp(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return clock(date, calendar: calendar) }
        if isYesterday(date, now: now, calendar: calendar) { return "昨天 " + clock(date, calendar: calendar) }
        return monthDay(date, calendar: calendar) + " " + clock(date, calendar: calendar)
    }

    /// The widget footer: 「22:10 更新」/「昨天 22:10 更新」/「10月29日 22:10 更新」.
    public static func widgetUpdated(_ date: Date, now: Date, calendar: Calendar) -> String {
        stamp(date, now: now, calendar: calendar) + " 更新"
    }

    /// The small widget's stale line has room for one of them only: 「8:10」 today, else the day
    /// alone, 「昨天」 or 「10月29日」 (the day matters more than the clock once it is not today).
    public static func dayOrClock(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return clock(date, calendar: calendar) }
        if isYesterday(date, now: now, calendar: calendar) { return "昨天" }
        return monthDay(date, calendar: calendar)
    }

    /// A 最近 row: 「刚刚」/「今天 09:12」/「昨天 22:14」/「周一 19:02」/「10月20日 19:02」. In the
    /// school's calendar (as 昨天花了 is), so a phone set to another time zone counts the same days.
    public static func recent(_ date: Date, now: Date, calendar: Calendar = SchoolCalendar.shanghai) -> String {
        let age = now.timeIntervalSince(date)
        if age >= 0, age < 300 { return "刚刚" }
        let parts = calendar.dateComponents([.month, .day, .hour, .minute, .weekday], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return "今天 " + time }
        if isYesterday(date, now: now, calendar: calendar) { return "昨天 " + time }
        if age > 0, age < 6 * 86400 {
            return "周" + ["日", "一", "二", "三", "四", "五", "六"][(parts.weekday ?? 1) - 1] + " " + time
        }
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日 " + time
    }

    static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }

    static func isYesterday(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
        return calendar.isDate(date, inSameDayAs: yesterday)
    }
}
