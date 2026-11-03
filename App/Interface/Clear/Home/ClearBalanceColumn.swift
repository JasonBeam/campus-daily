import SwiftUI
import Core

/// One column of 电量和校园卡: label, big number and unit, the small line under it, and its
/// top-up link. The number and lines are one VoiceOver element; the link is its own button.
struct ClearBalanceColumn: View {
    let title: String
    let figure: HomeFigure
    /// Nil shows 「—」.
    let value: String?
    let unit: String
    let spoken: String
    /// 「电费余额 ¥23.40」.
    let extra: String?
    /// 「充电费 ›」; nil hides it (signed out, no meter).
    let link: String?
    let openLink: () -> Void
    /// 「还没找到电表 · 去设置」.
    let openMeter: () -> Void
    @ScaledMetric(relativeTo:.largeTitle) private var valueSize: CGFloat = 34

    var body: some View {
        VStack(alignment:.leading, spacing:10) {
            figureBlock
            if let link {
                Button(link, action:openLink)
                    .font(.subheadline).foregroundStyle(Theme.accentText)
                    .buttonStyle(.plain)
                    // 20 to the eye, 44 to the finger.
                    .padding(.vertical,12).contentShape(Rectangle()).padding(.vertical,-12)
                    .accessibilityLabel(String(link.dropLast(2)))
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }

    @ViewBuilder private var figureBlock: some View {
        if figure.subline == .meterNotFound {
            // The line is a link to the meter picker.
            Button(action:openMeter) { numbers }
                .buttonStyle(.plain)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(.isButton)
        } else {
            numbers
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(spoken)
        }
    }

    private var numbers: some View {
        VStack(alignment:.leading, spacing:6) {
            Text(title).font(.subheadline).foregroundStyle(Theme.ink2)
            HStack(alignment:.firstTextBaseline, spacing:4) {
                Text(value ?? "—")
                    .font(.system(size:valueSize, weight:.semibold)).monospacedDigit()
                    .foregroundStyle(value == nil ? Theme.ink3 : figure.low ? Theme.redLarge : Theme.ink)
                    .contentTransition(.numericText())
                if value != nil { Text(unit).font(.caption).foregroundStyle(Theme.ink2) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            VStack(alignment:.leading, spacing:4) {
                subline
                if let extra { Text(extra).foregroundStyle(Theme.ink2).monospacedDigit() }
            }
            .font(.caption)
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var subline: some View {
        switch figure.subline {
        case .findingMeter?:
            HStack(spacing:6) {
                ProgressView().controlSize(.mini)
                Text(HomeFigure.Subline.findingMeter.text)
            }
            .foregroundStyle(Theme.ink2)
        case let line?:
            Text(line.text)
                .foregroundStyle(figure.low ? Theme.redText : line == .meterNotFound ? Theme.accentText : Theme.ink2)
                .monospacedDigit()
                .fixedSize(horizontal:false, vertical:true)
        case nil:
            EmptyView()
        }
    }
}
