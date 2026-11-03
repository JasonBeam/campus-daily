import SwiftUI

/// The running order's 「18 分钟」 and its progress bar, ticking each minute.
struct ClearLaundryRemaining: View {
    let end: Date
    /// Program length in minutes, when the machine lists it (drives the bar).
    let minutes: Int?

    var body: some View {
        TimelineView(minuteSchedule(to:end)) { context in
            let left = LaundryFormat.minutesLeft(until:end, now:context.date)
            VStack(alignment:.leading, spacing:12) {
                Text("\(left) 分钟")
                    .font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(countsDown:true))
                    .animation(.default, value:left)
                if let minutes, minutes > 0 {
                    let fraction = min(1, max(0, 1 - end.timeIntervalSince(context.date) / Double(minutes * 60)))
                    ProgressView(value:fraction).tint(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("还剩 \(left) 分钟")
        }
    }
}
