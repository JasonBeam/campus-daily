import SwiftUI
import Core

/// Trailing value of a status row.
enum RowValue: Equatable {
    case number(String, unit: String?, low: Bool)
    case word(String)
    /// Needs attention but isn't "running out": accentText.
    case accentWord(String)
    /// Laundry running: 「还剩」 + minutes + 「分钟」, same anatomy as 电量. Ticks each minute.
    case countdown(end: Date)
    /// Order amount: 20 semibold rounded, ink (laundry 「这笔订单」).
    case amount(String)
    case dash
}

/// Minute ticks aligned to `end` (each tick is a whole number of minutes before it).
func minuteSchedule(to end: Date) -> PeriodicTimelineSchedule {
    .periodic(from:end.addingTimeInterval(-86400), by:60)
}

/// Icon column width shared by StatusRow and RecentRow (scaled like .title2) so text edges line up.
enum RowMetrics { static let iconColumn: CGFloat = 28 }

/// Home status row: icon · title/subtitle · value. Min height 66.
struct StatusRow: View {
    /// SF Symbol name (`RowIcon`).
    let symbol: String
    let title: String
    var subtitle: String = ""
    var subtitleLow = false
    var value: RowValue?
    var dimmed = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.title2) private var iconColumn: CGFloat = RowMetrics.iconColumn
    var body: some View {
        // Accessibility sizes: the icon sits on the first title line's baseline, not the stack's centre.
        HStack(alignment:typeSize.isAccessibilitySize ? .firstTextBaseline : .center, spacing:14) {
            RowIcon(symbol:symbol).frame(width:iconColumn)
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading, spacing:6) { titles; valueView }
                Spacer(minLength:0)
            } else {
                titles
                Spacer(minLength:8)
                valueView
            }
        }
        .padding(.vertical,10).frame(minHeight:66)
        .padding(.horizontal,24)
    }
    private var titles: some View {
        VStack(alignment:.leading, spacing:2) {
            Text(title).scaledFont(17, .medium).foregroundStyle(dimmed ? Theme.ink2 : Theme.ink)
            if !subtitle.isEmpty {
                Text(subtitle).scaledFont(13, relativeTo:.footnote)
                    .foregroundStyle(subtitleLow ? Theme.redText : Theme.ink2)
            }
        }.fixedSize(horizontal:false, vertical:true)
    }
    @ViewBuilder private var valueView: some View {
        switch value {
        case .number(let number, let unit, let low)?:
            HStack(alignment:.firstTextBaseline, spacing:3) {
                Text(number).scaledFont(24, .semibold, design:.rounded, relativeTo:.title2).monospacedDigit().tracking(-0.2)
                    .foregroundStyle(low ? Theme.redLarge : Theme.ink)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                if let unit { Text(unit).scaledFont(14, .medium, relativeTo:.subheadline).foregroundStyle(Theme.ink2) }
            }.lineLimit(1)
        case .word(let word)?:
            Text(word).scaledFont(17, .medium).foregroundStyle(Theme.ink2)
        case .accentWord(let word)?:
            Text(word).scaledFont(17, .medium).foregroundStyle(Theme.accentText)
        case .countdown(let end)?:
            TimelineView(minuteSchedule(to:end)) { context in
                HStack(alignment:.firstTextBaseline, spacing:0) {
                    Text("还剩").scaledFont(17, .medium).foregroundStyle(Theme.ink2).padding(.trailing,4)
                    Text("\(LaundryFormat.minutesLeft(until:end, now:context.date))")
                        .scaledFont(24, .semibold, design:.rounded, relativeTo:.title2).monospacedDigit().tracking(-0.2)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(countsDown:true))
                        .padding(.trailing,3)
                    Text("分钟").scaledFont(14, .medium, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                }.lineLimit(1).minimumScaleFactor(0.7)
            }
        case .amount(let text)?:
            Text(text).scaledFont(20, .semibold, design:.rounded, relativeTo:.title3).monospacedDigit()
                .foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
        case .dash?:
            Text("—").scaledFont(17, .medium).foregroundStyle(Theme.ink3)
        case nil:
            EmptyView()
        }
    }
}

/// 「最近」 row: min height 56, icon 20, 16pt text.
struct RecentRow: View {
    let item: RecentItem
    /// Replaces the amount with an accentText word (laundry 「待核对」).
    var accentWord: String? = nil
    /// Under a day header (校园卡记录): the time alone, 「12:05 · 示例面馆」.
    var clockOnly = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.title2) private var iconColumn: CGFloat = RowMetrics.iconColumn
    var body: some View {
        // Accessibility sizes: the icon sits on the first title line's baseline.
        HStack(alignment:typeSize.isAccessibilitySize ? .firstTextBaseline : .center, spacing:14) {
            RowIcon(symbol:item.symbol).frame(width:iconColumn)
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading, spacing:4) { titles; amountView }
                Spacer(minLength:0)
            } else {
                titles
                Spacer(minLength:8)
                amountView
            }
        }
        .padding(.vertical,8).frame(minHeight:56)
        .padding(.horizontal,24)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel([item.title, subtitle, accentWord ?? item.spokenAmount].compactMap { $0 }.joined(separator:"，"))
    }
    private var titles: some View {
        VStack(alignment:.leading, spacing:2) {
            Text(item.title).scaledFont(16, relativeTo:.callout).foregroundStyle(Theme.ink)
            Text(subtitle).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
        }.fixedSize(horizontal:false, vertical:true)
    }
    @ViewBuilder private var amountView: some View {
        if let accentWord {
            Text(accentWord).scaledFont(17, .medium).foregroundStyle(Theme.accentText)
        } else if let amount = item.amountText {
            Text(amount).scaledFont(16, .medium, relativeTo:.callout).monospacedDigit().foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private var subtitle: String {
        [clockOnly ? CardDays.clock(item.date) : Theme.when(item.date), item.detail].compactMap { $0 }.joined(separator:" · ")
    }
}

/// Section header 「最近」/「登录后会出现」.
struct HomeSectionHeader: View {
    let text: String
    var body: some View {
        Text(text).scaledFont(13, .semibold, relativeTo:.footnote).foregroundStyle(Theme.ink2)
            .padding(.horizontal,24).padding(.bottom,4)
            .frame(maxWidth:.infinity, alignment:.leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Hairline between rows: starts at x = 24 and runs to the trailing edge.
struct RowSeparator: View {
    var body: some View { Hairline().padding(.leading,24) }
}

/// 8pt accent dot that pulses 1 → 0.35 on a 1.6s loop (static under Reduce Motion).
struct PulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        Circle().fill(Theme.accent).frame(width:8, height:8)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration:0.8).repeatForever(autoreverses:true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// Bottom-dock pill label (60pt min height, grows with text; label capped at AX2 so it stays one line).
struct DockPillLabel: View {
    enum Style { case primary, busy, disabled, destructive }
    let title: String
    var symbol: String? = nil
    var style: Style = .primary
    var body: some View {
        HStack(spacing:8) {
            if style == .busy { ProgressView().tint(Theme.ink2).frame(width:18, height:18) }
            if let symbol { Image(systemName:symbol).font(.system(size:17, weight:.semibold)) }
            Text(title).scaledFont(18, .semibold, relativeTo:.headline)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .foregroundStyle(foreground)
        .padding(.horizontal,16)
        .frame(maxWidth:.infinity).frame(minHeight:60)
        .background(background, in:Capsule())
        .contentShape(Capsule())
    }
    private var foreground: Color {
        switch style {
        case .primary: return Theme.pillInk
        case .busy: return Theme.ink2
        case .disabled: return Theme.ink3
        case .destructive: return .white
        }
    }
    private var background: Color {
        switch style {
        case .primary: return Theme.pill
        case .busy, .disabled: return Theme.fill
        case .destructive: return Theme.redLarge
        }
    }
}

/// 60pt round dock button.
struct DockRoundLabel: View {
    let symbol: String
    var body: some View {
        Image(systemName:symbol).font(.system(size:22)).foregroundStyle(Theme.ink)
            .frame(width:60, height:60)
            .background(Theme.group, in:Circle())
            .overlay(Circle().strokeBorder(Theme.separator, lineWidth:0.5))
            .contentShape(Circle())
    }
}

/// Bottom dock container: same material and margins as the home dock.
struct DockBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing:12) { content }
            .padding(.top,18).padding(.horizontal,20)
            .frame(maxWidth:640)
            .frame(maxWidth:.infinity)
            .background {
                ZStack { Rectangle().fill(.ultraThinMaterial); Theme.bg.opacity(0.85) }.ignoresSafeArea(edges:.bottom)
            }
    }
}
