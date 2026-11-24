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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shades = Self.shades(shares)
        // The rows' 44pt targets touch: the faces sit 12 apart.
        FlowRow(spacing:8, lineSpacing:0) {
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
            // Faces taller than the 44pt target (accessibility sizes) keep 12 between rows too.
            .padding(.vertical,typeSize.isAccessibilitySize ? 6 : 0)
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
/// amount kept on one line. At accessibility sizes the amount may go under the name, the face a
/// rounded rectangle then (corner 16), the dot beside the first line. The dot grows with the text.
private struct CategoryCapsule: View {
    let share: SpendShare
    /// The counted dot's colour; nil for a ring.
    let shade: ThemeColor?
    @ScaledMetric(relativeTo:.footnote) private var dotSize: CGFloat = 8
    @ScaledMetric(relativeTo:.footnote) private var textSize: CGFloat = 13
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            face(RoundedRectangle(cornerRadius:16, style:.continuous)) {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.firstTextBaseline, spacing:0) { dotted; name.padding(.trailing,4); amount }
                    HStack(alignment:.firstTextBaseline, spacing:0) {
                        dotted
                        VStack(alignment:.leading, spacing:0) { name; amount }
                    }
                }
            }
        } else {
            face(Capsule()) {
                HStack(spacing:0) { dot.padding(.trailing,6); name.padding(.trailing,4); amount }
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }

    private var name: some View {
        Text(share.kind.title).foregroundStyle(share.included ? Theme.ink : Theme.ink2).lineLimit(1)
    }

    private var amount: some View {
        Text(SpendStatsText.wholeYuan(share.spent)).monospacedDigit().foregroundStyle(Theme.ink2).lineLimit(1)
    }

    /// The dot on the first line's middle (about a third of the text size above its baseline).
    private var dotted: some View {
        dot.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + textSize * 0.35 }
            .padding(.trailing,6)
    }

    private func face<S: InsettableShape, Content: View>(_ shape: S, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .scaledFont(13, relativeTo:.footnote)
            .padding(.horizontal,10).padding(.vertical,6)
            .frame(minHeight:32)
            .background {
                if share.included { shape.fill(theme == .clear ? AnyShapeStyle(NativeTheme.surface) : AnyShapeStyle(Theme.group)) }
            }
            .overlay {
                if !share.included {
                    shape.strokeBorder(theme == .clear ? AnyShapeStyle(Color(uiColor:.separator)) : AnyShapeStyle(Theme.ink3),
                                       lineWidth:1)
                }
            }
    }

    @ViewBuilder private var dot: some View {
        if let shade {
            Circle().fill(shade).frame(width:dotSize, height:dotSize)
        } else {
            Circle().strokeBorder(Theme.ink2, lineWidth:1.5 * dotSize / 8).frame(width:dotSize, height:dotSize)
        }
    }
}

/// Lays its subviews left to right at their size within a line, wrapping onto a new line when
/// the next doesn't fit.
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
                let size = subviews[index].sizeThatFits(Self.proposal(bounds.width))
                subviews[index].place(at:CGPoint(x:x, y:y + (row.height - size.height) / 2),
                                      proposal:ProposedViewSize(width:min(size.width, bounds.width), height:size.height))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    /// Each subview is offered the whole line: one that can wrap (large text) fits in it.
    private static func proposal(_ width: CGFloat) -> ProposedViewSize {
        ProposedViewSize(width:width.isFinite ? width : nil, height:nil)
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(Self.proposal(width))
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
