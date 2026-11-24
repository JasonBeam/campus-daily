//
//  SpendBarsChart.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// The stats' bars: one a day (7 / 30 days) or a week (this term), oldest first, on a 1pt
/// baseline, with the span's average as a dashed line. The highest bar (or the one looked at) is
/// opaque with its amount over it. Press and slide across to look at a bar; let go to go back to
/// the total. VoiceOver: one adjustable element, a bar at a time.
struct SpendBarsChart: View {
    enum Look: Equatable {
        /// Read: the bars, the average line, the highest bar's amount.
        case live
        /// Still reading: the bars' shape in `fill`, still, nothing to look at.
        case placeholder
        /// Nothing spent: every bar a `fill` stub.
        case empty
    }

    let bars: [SpendBar]
    let span: SpendSpan
    let look: Look
    /// Where the dashed line goes (a day's average, a week's for this term); nil for none.
    let average: Money?
    /// The bar looked at (its id); the chart sets it while pressed and through VoiceOver.
    @Binding var selected: String?
    let text: SpendStatsText
    /// The school's records start on this day (`yyyyMMdd`): bars before it can't be looked at.
    var coveredFrom: String?

    static let height: CGFloat = 112
    private static let reach: CGFloat = 0.86

    @GestureState private var touch: Touch = .none
    @State private var width: CGFloat = 0
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing:6) {
            plot
            axis
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(look == .live ? chartName : "")
        .accessibilityValue(look == .live ? spokenValue : "")
        .accessibilityHint(look == .live ? hint : "")
        .accessibilityAdjustableAction { direction in
            guard look == .live else { return }
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .accessibilityHidden(look != .live)
        .accessibilityIdentifier("spendBars")
    }

    // MARK: Plot

    private var spacing: CGFloat {
        switch span {
        case .week: return 10
        case .month: return 3
        case .term: return 6
        }
    }

    private var plot: some View {
        let maxFen = max(bars.map(\.spent.fen).max() ?? 0, 1)
        let lit = litIndex
        return ZStack(alignment:.bottomLeading) {
            // Behind the bars: hidden by the opaque one, faint through the others.
            if look == .live, let average, average.fen > 0 {
                let y = Self.height - min(CGFloat(average.fen) / CGFloat(maxFen), 1) * Self.reach * Self.height
                DashedLine()
                    .stroke(Theme.ink3, style:StrokeStyle(lineWidth:1, dash:[3, 3]))
                    .frame(height:1)
                    .offset(y:-(Self.height - y))
                    .allowsHitTesting(false)
            }

            HStack(alignment:.bottom, spacing:spacing) {
                ForEach(Array(bars.enumerated()), id:\.element.id) { index, bar in
                    barShape(index:index, bar:bar, maxFen:maxFen, lit:index == lit)
                }
            }
            .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.bottomLeading)

            if let lit, look == .live {
                let bar = bars[lit]
                let height = barHeight(bar, maxFen:maxFen)
                BarSlotRow(count:bars.count, spacing:spacing, slots:[lit]) {
                    Text(amount(bar))
                        .scaledFont(11, .semibold, relativeTo:.caption2, cap:15)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(value:Double(bar.spent.fen)))
                        .foregroundStyle(Theme.accentText)
                        .fixedSize()
                }
                .padding(.bottom, height * (grown ? 1 : 0) + 3)
                .frame(maxHeight:.infinity, alignment:.bottom)
                .allowsHitTesting(false)
            }

            Rectangle().fill(Theme.separator).frame(height:1)
        }
        .frame(height:Self.height)
        .frame(maxWidth:.infinity)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { width = proxy.size.width }
                .onChange(of:proxy.size.width) { _, new in width = new }
        })
        .contentShape(Rectangle())
        .simultaneousGesture(scrub)
        .onChange(of:touchedID) { _, new in selected = new }
        .sensoryFeedback(.selection, trigger:touchedID) { _, new in new != nil }
        // New amounts (another span, a category counted or left out): the bars move, at once with Reduce Motion.
        .animation(reduceMotion ? nil : .easeInOut(duration:0.25), value:bars)
        .animation(reduceMotion ? nil : .easeOut(duration:0.3), value:look)
        .onAppear { grow() }
    }

    private func barShape(index: Int, bar: SpendBar, maxFen: Int, lit: Bool) -> some View {
        let height = barHeight(bar, maxFen:maxFen)
        let stub = look == .empty || (look == .live && bar.spent.fen <= 0)
        let style: ThemeColor = switch look {
        case .placeholder, .empty: Theme.fill
        case .live where stub: open(bar) ? Theme.ink3 : Theme.fill
        case .live: lit ? Theme.mark : Theme.mark.opacity(0.32)
        }
        return UnevenRoundedRectangle(topLeadingRadius:stub ? 0 : min(4, height / 2),
                                      topTrailingRadius:stub ? 0 : min(4, height / 2), style:.continuous)
            .fill(style)
            .frame(height:stub ? 2 : max(height * (grown ? 1 : 0), 0))
            .frame(maxWidth:.infinity)
    }

    private func barHeight(_ bar: SpendBar, maxFen: Int) -> CGFloat {
        switch look {
        case .empty: return 2
        case .placeholder:
            return Self.placeholderShape[(bars.firstIndex(of:bar) ?? 0) % Self.placeholderShape.count] * Self.reach * Self.height
        case .live:
            guard bar.spent.fen > 0 else { return 2 }
            return max(CGFloat(bar.spent.fen) / CGFloat(maxFen) * Self.reach * Self.height, 3)
        }
    }

    /// The still shape drawn while reading.
    private static let placeholderShape: [CGFloat] = [0.38, 0.84, 0.68, 0.52, 0.9, 0.76, 0.6, 0.48, 0.88, 0.74, 0.58, 0.45]

    /// The bars grow from the baseline the first time they show (at once with Reduce Motion).
    private func grow() {
        guard !grown else { return }
        if reduceMotion || look != .live { grown = true } else { withAnimation(.easeOut(duration:0.35)) { grown = true } }
    }

    // MARK: Axis

    private var axis: some View {
        let slots = bars.indices.filter { bars[$0].axisLabel != nil }
        return ZStack(alignment:.topLeading) {
            // A line's height even without labels, so the chart doesn't move when they come.
            Text(verbatim:"今").hidden()
            BarSlotRow(count:bars.count, spacing:spacing, slots:slots) {
                ForEach(slots, id:\.self) { index in
                    Text(bars[index].axisLabel ?? "").foregroundStyle(Theme.ink2).fixedSize()
                }
            }
        }
        .scaledFont(11, relativeTo:.caption2, cap:17)
        .frame(maxWidth:.infinity, alignment:.leading)
        .accessibilityHidden(true)
    }

    // MARK: Looking at a bar

    /// The bar drawn opaque: the one looked at, else the highest.
    private var litIndex: Int? {
        guard look == .live else { return nil }
        if let selected, let index = bars.firstIndex(where:{ $0.id == selected }) { return index }
        guard let top = bars.map(\.spent.fen).max(), top > 0 else { return nil }
        return bars.firstIndex { $0.spent.fen == top }
    }

    /// A press on the bars: nothing is looked at (no haptic) until it is known to be sideways.
    enum Touch: Equatable {
        case none
        /// Down, not yet moved far enough to tell.
        case undecided
        /// Moved sideways first: the finger looks at bars, whichever way it goes after.
        case looking(x: CGFloat)
        /// Moved up or down first: the page scrolls, the bars are left alone until the finger lifts.
        case scrolling
    }

    /// How far the finger moves before its direction counts.
    static let decideDistance: CGFloat = 4

    /// What a touch becomes on moving by `moved`, from `touch`.
    static func touch(_ touch: Touch, moved: CGSize, at x: CGFloat) -> Touch {
        switch touch {
        case .scrolling: return .scrolling
        case .looking: return .looking(x:x)
        case .none, .undecided:
            let dx = abs(moved.width), dy = abs(moved.height)
            guard max(dx, dy) >= decideDistance else { return .undecided }
            return dx > dy ? .looking(x:x) : .scrolling
        }
    }

    /// Alongside the page's scrolling (`simultaneousGesture`), so a swipe that starts on the bars
    /// still scrolls.
    private var scrub: some Gesture {
        DragGesture(minimumDistance:0)
            .updating($touch) { value, state, _ in
                state = Self.touch(state, moved:value.translation, at:value.location.x)
            }
    }

    /// The bar under the finger, if it can be looked at.
    private var touchedID: String? {
        guard look == .live, case .looking(let x) = touch, width > 0, !bars.isEmpty else { return nil }
        let slot = (width + spacing) / CGFloat(bars.count)
        let index = min(max(Int(x / slot), 0), bars.count - 1)
        return open(bars[index]) ? bars[index].id : nil
    }

    private func open(_ bar: SpendBar) -> Bool { Self.canLook(at:bar, coveredFrom:coveredFrom) }

    /// Before the term's start day, or wholly before the school's first record (`coveredFrom`,
    /// `yyyyMMdd`): nothing to look at. A week bar counts once any of its days is covered.
    static func canLook(at bar: SpendBar, coveredFrom: String?) -> Bool {
        guard !bar.beforeStart else { return false }
        guard let coveredFrom else { return true }
        return (bar.days.last ?? bar.id) >= coveredFrom
    }

    private func step(_ delta: Int) {
        let open = bars.indices.filter { self.open(bars[$0]) }
        guard !open.isEmpty else { return }
        let current = selected.flatMap { id in open.firstIndex { bars[$0].id == id } }
        let next: Int = switch current {
        case nil: delta > 0 ? 0 : open.count - 1
        case let at?: min(max(at + delta, 0), open.count - 1)
        }
        selected = bars[open[next]].id
    }

    private var chartName: String {
        let unit = span == .term ? "周" : "天"
        return text.theme == .clear ? "每\(unit == "天" ? "日" : "周")支出" : "每\(unit)花的钱"
    }

    /// The day (week) looked at: 「11月19日，32.10 元」; nothing before one is.
    private var spokenValue: String {
        guard let selected, let bar = bars.first(where:{ $0.id == selected }) else { return "" }
        return text.spokenBar(bar)
    }

    private var hint: String {
        text.theme == .clear ? "上下轻扫逐个查看" : "上下轻扫一个个听"
    }

    /// Over the lit bar: whole yuan on the narrow 30-day bars, else to the fen.
    private func amount(_ bar: SpendBar) -> String {
        span == .month ? SpendStatsText.wholeYuan(bar.spent) : SpendStatsText.yuan(bar.spent)
    }
}

/// A horizontal line across its frame, for the dashed average.
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to:CGPoint(x:rect.minX, y:rect.midY)); $0.addLine(to:CGPoint(x:rect.maxX, y:rect.midY)) }
    }
}

/// Lays its subviews, one per slot, centred under bar `slots[i]` of `count` evenly spaced bars,
/// pulled in at the edges so none sticks out. As tall as the tallest.
struct BarSlotRow: Layout {
    let count: Int
    let spacing: CGFloat
    let slots: [Int]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width:proposal.width ?? 0, height:height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard count > 0 else { return }
        let barWidth = max((bounds.width - spacing * CGFloat(count - 1)) / CGFloat(count), 0)
        for (subview, slot) in zip(subviews, slots) {
            let size = subview.sizeThatFits(.unspecified)
            let center = bounds.minX + CGFloat(slot) * (barWidth + spacing) + barWidth / 2
            let x = min(max(center - size.width / 2, bounds.minX), bounds.maxX - size.width)
            subview.place(at:CGPoint(x:x, y:bounds.minY), proposal:.unspecified)
        }
    }
}
