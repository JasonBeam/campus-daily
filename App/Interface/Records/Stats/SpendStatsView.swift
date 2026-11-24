//
//  SpendStatsView.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// The records page's spending stats on the page itself (no card): 「7 天 · 30 天 · 本学期」,
/// the total with the daily average, a bar a day (a week for this term), the categories, this
/// term's start day and what is counted. Pressing along the bars shows one day in the total's
/// place until let go. The host sets the side margins (暖橙 24, 清爽 the list's).
struct SpendStatsView: View {
    enum Phase: Equatable {
        case loading
        case failed
        case loaded(SpendStats)
    }

    let phase: Phase
    @Binding var span: SpendSpan
    /// The bars' shape drawn while reading (their amounts unused); empty for none yet.
    var placeholder: [SpendBar] = []
    /// This term's start day, for the 「改开学日」 row under 本学期; nil hides it.
    var term: TermStartSheet.Term?
    /// A day picked on 开学日, or nil for back to the default.
    var setTermStart: (Date?) -> Void = { _ in }
    /// The bar looked at when the view appears (screenshots).
    var pinned: String?
    /// The records' calendar (`CardRecordsModel.calendar`): days are named and picked in it.
    let calendar: Calendar

    @State private var selected: String?
    @State private var termSheet = false
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(phase: Phase, span: Binding<SpendSpan>, placeholder: [SpendBar] = [], term: TermStartSheet.Term? = nil,
         setTermStart: @escaping (Date?) -> Void = { _ in }, pinned: String? = nil, calendar: Calendar) {
        self.phase = phase; _span = span; self.placeholder = placeholder; self.term = term
        self.setTermStart = setTermStart; self.pinned = pinned; self.calendar = calendar
        _selected = State(initialValue:pinned)
    }

    private var text: SpendStatsText { SpendStatsText(theme:theme, calendar:calendar) }
    private var stats: SpendStats? { if case .loaded(let stats) = phase, stats.span == span { return stats }; return nil }
    private var loading: Bool { phase == .loading || (stats == nil && phase != .failed) }
    private var empty: Bool { stats?.isEmpty == true }
    private var selectedBar: SpendBar? { selected.flatMap { id in stats?.bars.first { $0.id == id } } }

    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            SpendSpanSwitch(span:$span)
            if phase == .failed {
                failedLine.padding(.top,10)
            } else {
                headline.padding(.top,10)
                chart.padding(.top,20)
                if let stats, !stats.isEmpty, !stats.shares.isEmpty {
                    SpendShareFlow(shares:stats.shares).padding(.top,18)
                }
            }
            if span == .term, let term { termRow(term).padding(.top,8) }
            notes
            Text(text.footnote)
                .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal:false, vertical:true)
                .padding(.top,span == .term && term != nil ? 4 : 14)
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .onChange(of:span) { _, _ in selected = nil }
        .onChange(of:pinned) { _, new in selected = new }
        .sheet(isPresented:$termSheet) {
            if let term { TermStartSheet(term:term, calendar:calendar, onDone:setTermStart) }
        }
    }

    // MARK: Headline

    /// The label, the big number and the line under it; a looked-at bar takes their place.
    /// Always as tall, so nothing below moves.
    private var headline: some View {
        VStack(alignment:.leading, spacing:0) {
            if empty, let stats {
                Text(text.empty(stats.span))
                    .scaledFont(22, .semibold, design:theme.numberDesign, relativeTo:.title2)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal:false, vertical:true)
                    .frame(minHeight:52, alignment:.leading)
            } else {
                Text(label)
                    .scaledFont(15, .semibold, relativeTo:.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
                hero.frame(minHeight:52, alignment:.leading)
                line
            }
        }
        .accessibilityElement(children:.combine)
        .accessibilityLabel(spokenHeadline)
        .accessibilityIdentifier("spendHeadline")
    }

    private var label: String {
        if let bar = selectedBar { return text.barLabel(bar) }
        return text.totalLabel(span)
    }

    @ViewBuilder private var hero: some View {
        if loading {
            HStack(spacing:6) {
                ProgressView().controlSize(.mini).frame(width:12, height:12)
                Text(text.loading(span))
                    .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
            }
        } else if let bar = selectedBar, bar.spent == .zero {
            Text(text.nothingSpent)
                .scaledFont(22, .semibold, design:theme.numberDesign, relativeTo:.title2)
                .foregroundStyle(Theme.ink)
        } else {
            let money = selectedBar?.spent ?? stats?.total ?? .zero
            HStack(alignment:.firstTextBaseline, spacing:3) {
                Text("¥").scaledFont(17, .medium, design:theme.numberDesign, relativeTo:.headline).foregroundStyle(Theme.ink2)
                Text(SpendStatsText.number(money))
                    .scaledFont(theme.heroSize, .semibold, design:theme.numberDesign, relativeTo:.largeTitle)
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(reduceMotion ? .identity : .numericText(value:Double(money.fen)))
                    .animation(reduceMotion ? nil : .easeInOut(duration:0.25), value:money)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    /// Under the number: the average and comparison, or a looked-at day's against the average.
    /// Kept as a blank line when there is nothing to say, so the chart stays put.
    private var line: some View {
        var parts: [SpendStatsText.Part]?
        if let stats {
            if let bar = selectedBar { parts = text.barLine(bar, average:stats.dailyAverage) } else { parts = text.averageLine(stats) }
        }
        return Group {
            if let parts {
                parts.reduce(Text(verbatim:"")) { line, part in
                    let run = part.strong ? Text(part.text).fontWeight(.semibold).foregroundStyle(Theme.ink)
                                          : Text(part.text).foregroundStyle(Theme.ink2)
                    return Text("\(line)\(run)")
                }
            } else {
                Text(" ").accessibilityHidden(true)
            }
        }
        .scaledFont(13, relativeTo:.footnote)
        .monospacedDigit()
        .fixedSize(horizontal:false, vertical:true)
    }

    private var spokenHeadline: String {
        if loading { return text.totalLabel(span) + "，" + text.loading(span) }
        guard let stats else { return "" }
        if stats.isEmpty { return text.empty(stats.span) }
        if let bar = selectedBar {
            var words = bar.spent == .zero ? text.barLabel(bar) + "，" + text.nothingSpent
                                           : text.barLabel(bar) + " " + bar.spent.yuanText + " 元"
            if let line = text.barLine(bar, average:stats.dailyAverage) { words += "，" + line.map(\.text).joined() }
            return words
        }
        return text.spokenSummary(stats)
    }

    // MARK: Chart

    @ViewBuilder private var chart: some View {
        if let stats {
            SpendBarsChart(bars:stats.bars, span:span, look:stats.isEmpty ? .empty : .live,
                           average:average(stats), selected:$selected, text:text, coveredFrom:stats.coveredFrom)
        } else {
            SpendBarsChart(bars:placeholderBars, span:span, look:.placeholder, average:nil,
                           selected:.constant(nil), text:text)
        }
    }

    /// The dashed line: the daily average, a week's worth of it for this term's week bars.
    private func average(_ stats: SpendStats) -> Money {
        stats.span == .term ? Money(fen:stats.dailyAverage.fen * 7) : stats.dailyAverage
    }

    /// The span's bars while reading: the host's, else the span's own shape.
    private var placeholderBars: [SpendBar] {
        if !placeholder.isEmpty { return placeholder }
        return SpendBarsPlaceholder.bars(span, termStart:term?.start ?? Date(), calendar:calendar)
    }

    // MARK: Lines under the chart

    private var failedLine: some View {
        HStack(alignment:.firstTextBaseline, spacing:5) {
            Image(systemName:"exclamationmark.circle.fill").accessibilityHidden(true)
            Text(SpendStatsText.failed).fixedSize(horizontal:false, vertical:true)
        }
        .scaledFont(13, relativeTo:.footnote)
        .foregroundStyle(theme == .clear ? NativeTheme.notice : Theme.notice)
        .accessibilityElement(children:.combine)
        .frame(minHeight:44, alignment:.leading)
        .accessibilityIdentifier("spendFailed")
    }

    private func termRow(_ term: TermStartSheet.Term) -> some View {
        let range = text.termRange(term.start)
        return Button { termSheet = true } label: {
            HStack(alignment:.firstTextBaseline, spacing:0) {
                Text(range.text).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                Text(range.action).scaledFont(15, .medium, relativeTo:.subheadline).foregroundStyle(Theme.accentText)
            }
            .frame(minHeight:44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(text.spokenTermRange(term.start))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("termStartRow")
    }

    @ViewBuilder private var notes: some View {
        if let stats {
            if let covered = stats.coveredFrom.flatMap(text.coveredFrom) {
                Text(covered)
                    .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.top,14)
            }
            if stats.unsureDays > 0 {
                HStack(alignment:.firstTextBaseline, spacing:5) {
                    Image(systemName:"exclamationmark.circle").accessibilityHidden(true)
                    Text(text.unsureDays(stats.unsureDays)).fixedSize(horizontal:false, vertical:true)
                }
                .scaledFont(13, relativeTo:.footnote)
                .foregroundStyle(NativeTheme.notice)
                .accessibilityElement(children:.combine)
                .padding(.top,10)
            }
        }
    }
}
