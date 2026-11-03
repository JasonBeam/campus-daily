import SwiftUI
import Core

/// 2.3, the 本次费用 card. While water runs it also holds the timer (「用时」), in place of
/// 暖橙's large one.
struct ClearShowerCostCard: View {
    @EnvironmentObject private var shower: ShowerModel
    /// Nil: no session to show (ready to start).
    let phase: ShowerPagePhase?
    let live: Bool

    private var page: ShowerPage? { shower.page.page }

    var body: some View {
        VStack(alignment:.leading, spacing:14) {
            if phase == .running {
                ClearShowerCostRow(label:"用时") { timer }
                Divider()
            }
            ClearShowerCostRow(label:"本次费用") { cost }
        }
        .padding(18)
        .background(NativeTheme.surface, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }

    @ViewBuilder private var cost: some View {
        switch phase {
        case .done?:
            // Only the platform's amount is ever shown.
            if let amount = page?.amount {
                Text("¥" + amount.yuanText).font(.title2.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("\(amount.yuanText) 元")
            } else {
                missing
            }
        case nil where live && shower.state.phase == .done:
            if let cost = shower.lastCost {
                Text(Theme.yuan(cost)).font(.title2.weight(.semibold)).monospacedDigit()
            } else {
                missing
            }
        default:
            Text("结算后显示").font(.subheadline)
        }
    }

    private var missing: some View {
        Text("没拿到金额").font(.subheadline).foregroundStyle(.secondary)
    }

    @ViewBuilder private var timer: some View {
        let start = page?.startedAt ?? Date()
        Text(timerInterval:start...Date.distantFuture, countsDown:false)
            .font(.title.weight(.semibold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.7)
            .accessibilityHidden(true)
            .overlay {
                // VoiceOver reads the elapsed time in words, refreshed at most every 30 s.
                TimelineView(.periodic(from:start, by:30)) { context in
                    Color.clear.accessibilityElement()
                        .accessibilityLabel(ShowerPageText.elapsed(since:start, now:context.date))
                }
            }
    }
}
