import Foundation

/// Number and time formats shared by the app (Theme) and the widget.
enum CampusFormat {
    private static let posix = Locale(identifier:"en_US_POSIX")
    /// 「¥86.50」
    static func yuan(_ value: Decimal) -> String {
        "¥" + plainYuan(value)
    }
    /// 「86.50」 (VoiceOver labels say 「元」 after it).
    static func plainYuan(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(posix))
    }
    /// 「42.6」
    static func kwh(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(posix))
    }
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posix; formatter.dateFormat = "HH:mm"
        return formatter.string(from:date)
    }
    /// 「10:32 更新」/「昨天 22:10 更新」/「10月26日更新」
    static func updated(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs:now) { return clock(date) + " 更新" }
        if calendar.isDateInYesterday(date) { return "昨天 " + clock(date) + " 更新" }
        let parts = calendar.dateComponents([.month,.day], from:date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日更新"
    }
}
