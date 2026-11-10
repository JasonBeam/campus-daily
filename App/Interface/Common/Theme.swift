import SwiftUI
import Core

/// Design tokens. The colours are `ThemeColor`s, resolved from the theme in the view's
/// environment (`\.appTheme`) where they are drawn; the other tokens are `AppTheme`'s
/// (`AppTheme+Tokens`).
enum Theme {
    static let bg = ThemeColor(.bg)
    static let group = ThemeColor(.group)
    static let ink = ThemeColor(.ink)
    static let ink2 = ThemeColor(.ink2)
    static let ink3 = ThemeColor(.ink3)
    static let separator = ThemeColor(.separator)
    static let fill = ThemeColor(.fill)
    static let accent = ThemeColor(.accent)
    static let accentLarge = ThemeColor(.accentLarge)
    static let accentText = ThemeColor(.accentText)
    /// Label on an `accent` background: white in light, #111 in dark (清爽: white in both).
    static let accentInk = ThemeColor(.accentInk)
    static let redLarge = ThemeColor(.redLarge)
    static let redText = ThemeColor(.redText)
    static let pill = ThemeColor(.pill)
    static let pillInk = ThemeColor(.pillInk)
    /// Problems that aren't "running out": errors, 「暂停」, what the school refused. accentText in 暖橙.
    static let notice = ThemeColor(.notice)
    /// Line icons at the start of rows and beside labels: ink2 in 暖橙, accentText in 清爽.
    static let icon = ThemeColor(.icon)
    /// A shut text entry (「先看看示例」 refused): ink2 in 暖橙, #6C6C70 / #AEAEB2 in 清爽.
    static let disabledText = ThemeColor(.disabledText)

    /// UI copy language for `.typesettingLanguage(_:)`.
    static let typesetting = Locale.Language(identifier:"zh-Hans")

    static let spring = Animation.spring(response:0.45, dampingFraction:0.82)
    static let pressSpring = Animation.spring(response:0.3, dampingFraction:0.6)

    /// "3栋108" → "3 栋 108"; nil when unknown.
    static func dorm(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in:.whitespaces)
        guard !value.isEmpty, value != "未配置" else { return nil }
        let parts = value.split(separator:"栋", maxSplits:1).map { $0.trimmingCharacters(in:.whitespaces) }
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { return parts[0] + " 栋 " + parts[1] }
        return value
    }
    static func yuan(_ value: Decimal) -> String { CampusFormat.yuan(value) }
    static func kwh(_ value: Decimal) -> String { CampusFormat.kwh(value) }
    /// 「10:32 更新」/「昨天 22:10 更新」/「10月26日更新」 (shared with the widget).
    static func updated(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        CampusFormat.updated(date, now:now, calendar:calendar)
    }
    /// Recent-row time: 「刚刚」/「今天 09:12」/「昨天 22:14」/「周一 19:02」/「10月20日 19:02」
    static func when(_ date: Date, now: Date = Date()) -> String {
        UpdateTimeText.recent(date, now:now)
    }
}

/// System font at a Dynamic Type–scaled size.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let cap: CGFloat?
    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle, cap: CGFloat?) {
        _size = ScaledMetric(wrappedValue:size, relativeTo:style)
        self.weight = weight; self.design = design; self.cap = cap
    }
    func body(content: Content) -> some View {
        content.font(.system(size:cap.map { min(size, $0) } ?? size, weight:weight, design:design))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default,
                    relativeTo style: Font.TextStyle = .body, cap: CGFloat? = nil) -> some View {
        modifier(ScaledFont(size:size, weight:weight, design:design, relativeTo:style, cap:cap))
    }
}

/// Dock pills / round button: scale 0.96 on press.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.pressSpring, value:configuration.isPressed)
    }
}

/// List rows: opacity 0.5 on press, no highlight fill.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.5 : 1).contentShape(Rectangle())
    }
}

/// 0.5pt hairline in `separator`.
struct Hairline: View {
    @Environment(\.displayScale) private var scale
    var body: some View { Rectangle().fill(Theme.separator).frame(height:1 / scale) }
}
