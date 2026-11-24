//
//  SpendShareFlow.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// The span's categories as small capsules that wrap: those spent on and those left out (at ¥0
/// too, so they can come back), in the stats' fixed order. Counted: a filled capsule, a solid dot
/// from the chart accent (`Theme.mark`) down its lighter shades in the order of those counted
/// (「其他」 ink3), the name in ink. Left out: an outline, a ring, the name in ink2. A tap counts a
/// category or leaves it out (`toggle`); the last one counted is refused with a warning and a blink.
/// Without `toggle` (made-up demos) they only show.
struct SpendShareFlow: View {
    let shares: [SpendShare]
    /// Every category counted, listed or not (`CardRecordsModel.includedCategories`): the last
    /// one can't be turned off.
    let counted: Set<CardRecordKind>
    /// Switches a category; false when refused.
    var toggle: ((CardRecordKind) -> Bool)?

    @State private var switched = 0
    @State private var refused = 0
    @State private var blinks: [CardRecordKind: Int] = [:]
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shades = Self.shades(shares)
        FlowRow(spacing:8, lineSpacing:6) {
            ForEach(shares) { share in
                capsule(share, shade:shades[share.kind])
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .sensoryFeedback(.selection, trigger:switched)
        .sensoryFeedback(.warning, trigger:refused)
    }

    @ViewBuilder private func capsule(_ share: SpendShare, shade: ThemeColor?) -> some View {
        let face = CategoryCapsule(share:share, shade:shade)
            .keyframeAnimator(initialValue:1.0, trigger:blinks[share.kind, default:0]) { content, opacity in
                content.opacity(opacity)
            } keyframes: { _ in
                LinearKeyframe(0.5, duration:0.075)
                LinearKeyframe(1.0, duration:0.075)
            }
            .frame(minHeight:44)
            .contentShape(Rectangle())
        if let toggle {
            Button { tap(share.kind, toggle:toggle) } label: { face }
                .buttonStyle(.plain)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(SpendStatsText.spokenShare(share))
                .accessibilityValue(SpendStatsText.categoryValue(share))
                .accessibilityHint(SpendStatsText.categoryHint(share, counted:counted))
                .accessibilityAddTraits([.isButton, .isToggle])
                .accessibilityIdentifier("spendCategory-\(share.kind.rawValue)")
        } else {
            face
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(SpendStatsText.spokenShare(share))
                .accessibilityValue(SpendStatsText.categoryValue(share))
        }
    }

    private func tap(_ kind: CardRecordKind, toggle: (CardRecordKind) -> Bool) {
        let done = withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) { toggle(kind) }
        if done {
            switched += 1
        } else {
            refused += 1
            if !reduceMotion { blinks[kind, default:0] += 1 }
        }
    }

    /// Accent at 100 / 62 / 38 / 22% down those counted, in order; 「其他」 always ink3. Those
    /// left out get none (a ring).
    static func shades(_ shares: [SpendShare]) -> [CardRecordKind: ThemeColor] {
        var shades: [CardRecordKind: ThemeColor] = [:]
        for (index, share) in shares.filter(\.included).enumerated() { shades[share.kind] = color(share.kind, at:index) }
        return shades
    }

    static func color(_ kind: CardRecordKind, at index: Int) -> ThemeColor {
        guard kind != .other else { return Theme.ink3 }
        let steps = [1, 0.62, 0.38, 0.22]
        return Theme.mark.opacity(steps[min(index, steps.count - 1)])
    }
}

/// One capsule's face: 32 high (taller with the text), the dot, the name and the whole-yuan
/// amount kept on one line.
private struct CategoryCapsule: View {
    let share: SpendShare
    /// The counted dot's colour; nil for a ring.
    let shade: ThemeColor?
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing:0) {
            dot.padding(.trailing,6)
            Text(share.kind.title).foregroundStyle(share.included ? Theme.ink : Theme.ink2)
                .padding(.trailing,4)
            Text(SpendStatsText.wholeYuan(share.spent)).monospacedDigit().foregroundStyle(Theme.ink2)
        }
        .scaledFont(13, relativeTo:.footnote)
        .lineLimit(1)
        .padding(.horizontal,10).padding(.vertical,6)
        .frame(minHeight:32)
        .background {
            if share.included { Capsule().fill(theme == .clear ? AnyShapeStyle(NativeTheme.surface) : AnyShapeStyle(Theme.group)) }
        }
        .overlay {
            if !share.included {
                Capsule().strokeBorder(theme == .clear ? AnyShapeStyle(Color(uiColor:.separator)) : AnyShapeStyle(Theme.ink3),
                                       lineWidth:1)
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var dot: some View {
        if let shade {
            Circle().fill(shade).frame(width:8, height:8)
        } else {
            Circle().strokeBorder(Theme.ink2, lineWidth:1.5).frame(width:8, height:8)
        }
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
