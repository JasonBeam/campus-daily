import Foundation

/// 清爽's amounts on the laundry page, its sheets' neighbours and the 订单 tab: the system
/// currency format for CNY in the user's locale (「CN¥4.00」 outside mainland China's region).
enum ClearCNY {
    static func text(_ value: Decimal, locale: Locale = .current) -> String {
        value.formatted(.currency(code:"CNY").locale(locale))
    }
}
