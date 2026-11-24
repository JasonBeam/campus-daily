//
//  SpendShareFlow.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// The span's categories as one line of small words that wraps: a dot, the name in ink and the
/// whole-yuan amount in ink2. The dots go from the chart accent (`Theme.mark`) to its lighter shades, biggest first;
/// 「其他」 is ink3. VoiceOver reads each with the full amount and its share.
struct SpendShareFlow: View {
    let shares: [SpendShare]

    var body: some View {
        FlowRow(spacing:16, lineSpacing:6) {
            ForEach(Array(shares.enumerated()), id:\.element.id) { index, share in
                HStack(spacing:5) {
                    Circle().fill(Self.color(share.kind, at:index)).frame(width:8, height:8)
                    Text(share.kind.title).foregroundStyle(Theme.ink)
                    Text(SpendStatsText.wholeYuan(share.spent)).monospacedDigit().foregroundStyle(Theme.ink2)
                }
                .scaledFont(13, relativeTo:.footnote)
                .fixedSize()
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(SpendStatsText.spokenShare(share))
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }

    /// Accent at 100 / 62 / 38 / 22% in order; 「其他」 always ink3.
    static func color(_ kind: CardRecordKind, at index: Int) -> ThemeColor {
        guard kind != .other else { return Theme.ink3 }
        let steps = [1, 0.62, 0.38, 0.22]
        return Theme.mark.opacity(steps[min(index, steps.count - 1)])
    }
}

/// Lays its subviews left to right, wrapping onto a new line when the next doesn't fit.
struct FlowRow: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width:proposal.width ?? .infinity, subviews:subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width:proposal.width ?? width, height:height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width:bounds.width, subviews:subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at:CGPoint(x:x, y:y + (row.height - size.height) / 2),
                                      proposal:ProposedViewSize(width:min(size.width, bounds.width), height:size.height))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, next > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
