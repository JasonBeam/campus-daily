import SwiftUI
import Core

/// One column of 双余额: label, big number and unit, two small lines and the read time. One
/// VoiceOver element.
struct ClearBalanceColumn: View {
    let title: String
    /// 「42.60」, or 「—」.
    let value: String
    let unit: String
    /// Running out: the number in red.
    let low: Bool
    let lines: [String]
    /// 「查询 7:01」; nil before any read.
    let stamp: String?
    @ScaledMetric(relativeTo:.largeTitle) private var valueSize: CGFloat = 34

    var body: some View {
        VStack(alignment:.leading, spacing:10) {
            Text(title).font(.subheadline).foregroundStyle(Theme.ink2)
            HStack(alignment:.firstTextBaseline, spacing:4) {
                Text(value)
                    .font(.system(size:valueSize, weight:.semibold)).monospacedDigit()
                    .foregroundStyle(low ? Theme.redLarge : Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(unit).font(.caption).foregroundStyle(Theme.ink2)
            }
            VStack(alignment:.leading, spacing:6) {
                ForEach(lines, id:\.self) { Text($0).monospacedDigit() }
            }
            .font(.caption).foregroundStyle(Theme.ink2)
            if let stamp { Text(stamp).font(.caption2).foregroundStyle(Theme.ink2) }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .accessibilityElement(children:.combine)
    }
}
