import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

/// Laundry Live Activity views: same visual system as the shower activity, no button.
/// Compiled into the widget (the real activity) and the app (DEBUG preview only).
enum LaundryActivityStyle {
    static let accent = Color(red:1, green:138 / 255, blue:69 / 255) // #FF8A45
    static let background = Color(white:0.07).opacity(0.82)
    static let glyph = "washer.fill"
    static func rounded(_ size: CGFloat) -> Font { .system(size:size, weight:.semibold, design:.rounded) }
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.dateFormat = "HH:mm"
        return formatter.string(from:date)
    }
}

extension LaundryActivityAttributes.ContentState {
    var minutes: Int { max(0, minutesLeft) }
    var interval: ClosedRange<Date> { min(startedAt, endsAt)...endsAt }
    /// Done rendering: the app said so, the system marked the content stale (staleDate = end),
    /// or the end has passed without an update.
    func showsDone(stale: Bool, now: Date = .now) -> Bool { phase == .done || stale || endsAt <= now }
}

extension LaundryActivityAttributes {
    var runningTitle: String { "正在洗衣 · " + machine }
}

/// System countdown 「17:59」: 44 semibold rounded, ticks by itself. Callers guarantee end > now.
struct LaundryActivityCountdown: View {
    let end: Date
    var size: CGFloat = 44
    var body: some View {
        let now = Date.now
        Text(timerInterval:now...max(now, end), countsDown:true)
            .font(LaundryActivityStyle.rounded(size)).monospacedDigit().foregroundStyle(.white)
            .multilineTextAlignment(.leading).lineLimit(1)
    }
}

/// 4pt line, accent fill on a white 18% track. Moves by itself between updates.
struct LaundryActivityProgress: View {
    let state: LaundryActivityAttributes.ContentState
    var body: some View {
        ProgressView(timerInterval:state.interval, countsDown:false) { EmptyView() } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(LaundryActivityStyle.accent)
            .background(Capsule().fill(.white.opacity(0.18)).frame(height:4))
            .accessibilityHidden(true)
    }
}

struct LaundryActivityLockView: View {
    let attributes: LaundryActivityAttributes
    let state: LaundryActivityAttributes.ContentState
    var isStale = false
    var body: some View {
        let done = state.showsDone(stale:isStale)
        VStack(alignment:.leading, spacing:0) {
            HStack(spacing:6) {
                Image(systemName:LaundryActivityStyle.glyph)
                Text(done ? "衣服洗好了" : attributes.runningTitle)
                Spacer(minLength:8)
                Text("校日常").foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size:13, weight:.semibold)).foregroundStyle(LaundryActivityStyle.accent).lineLimit(1)
            if done {
                Text("去拿衣服吧").font(.system(size:26, weight:.bold)).foregroundStyle(.white).padding(.top,8)
                Text(attributes.machine).font(.system(size:13)).foregroundStyle(.white.opacity(0.55)).padding(.top,2)
            } else {
                LaundryActivityCountdown(end:state.endsAt).padding(.top,6)
                Text(LaundryActivityStyle.clock(state.endsAt) + " 洗完")
                    .font(.system(size:13)).foregroundStyle(.white.opacity(0.55))
                LaundryActivityProgress(state:state).padding(.top,12)
            }
        }
        .padding(.top,14).padding(.horizontal,16).padding(.bottom,16)
    }
}

/// Dynamic Island regions, shared so the DEBUG preview draws exactly what the widget draws.
struct LaundryIslandLeading: View {
    let attributes: LaundryActivityAttributes
    let state: LaundryActivityAttributes.ContentState
    var isStale = false
    var body: some View {
        let done = state.showsDone(stale:isStale)
        Text(done ? "衣服洗好了" : attributes.runningTitle)
            .font(.system(size:13, weight:.semibold))
            .foregroundStyle(done ? Color.white.opacity(0.55) : LaundryActivityStyle.accent)
            .lineLimit(1).fixedSize()
    }
}
struct LaundryIslandTrailing: View {
    let attributes: LaundryActivityAttributes
    let state: LaundryActivityAttributes.ContentState
    var isStale = false
    var body: some View {
        Text(state.showsDone(stale:isStale) ? attributes.machine : attributes.program)
            .font(.system(size:13, weight:.semibold)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
    }
}
struct LaundryIslandBottom: View {
    let state: LaundryActivityAttributes.ContentState
    var isStale = false
    var body: some View {
        VStack(alignment:.leading, spacing:2) {
            if state.showsDone(stale:isStale) {
                Text("去拿衣服吧").font(.system(size:26, weight:.bold)).foregroundStyle(.white)
            } else {
                LaundryActivityCountdown(end:state.endsAt, size:36)
                Text(LaundryActivityStyle.clock(state.endsAt) + " 洗完")
                    .font(.system(size:13)).foregroundStyle(.white.opacity(0.55))
                LaundryActivityProgress(state:state).padding(.top,8)
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }
}
struct LaundryIslandCompactTrailing: View {
    let state: LaundryActivityAttributes.ContentState
    var isStale = false
    var body: some View {
        let now = Date.now
        Group {
            if state.showsDone(stale:isStale, now:now) {
                Image(systemName:"checkmark").accessibilityLabel("衣服洗好了")
            } else {
                Text(timerInterval:now...max(now, state.endsAt), countsDown:true)
                    .monospacedDigit().multilineTextAlignment(.trailing)
            }
        }
        .font(LaundryActivityStyle.rounded(14)).foregroundStyle(LaundryActivityStyle.accent).lineLimit(1)
        .frame(width:52, alignment:.trailing)
    }
}
#endif
