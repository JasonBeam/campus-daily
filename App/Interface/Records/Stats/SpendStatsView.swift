//
//  SpendStatsView.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// The records page's spending stats on the page itself (no card): 「7 天 · 30 天 · 本学期」,
/// the total with the daily average, a bar a day (a week for this term), the categories (capsules
/// that count one or leave it out), this term's start day and what is counted. Pressing along
/// the bars shows one day in the total's place until let go. The host sets the side margins
/// (暖橙 24, 清爽 the list's).
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
    /// The period before the span is still read: the comparison is left out until it comes, its
    /// room kept.
    var comparing = false
    /// Counts a category or leaves it out (`CardRecordsModel.toggleCategory`); false when refused.
    /// Nil: the capsules only show.
    var toggleCategory: ((CardRecordKind) -> Bool)?
    /// Every category counted (`CardRecordsModel.includedCategories`); nil: those counted on the list.
    var counted: Set<CardRecordKind>?
    /// The records shown are those kept from before; the newest could not be read
    /// (`CardRecordsModel.refreshFailed`): a line says so under the span switch.
    var stale = false
    /// When the cached records were last saved (`CardRecordsModel.cachedSavedAt`).
    var staleSavedAt: Date?
    /// The cached history's anchor day (`CardRecordsModel.cachedToday`).
    var staleToday: Date?
    /// Wall clock used to distinguish same-day vs earlier-day offline copy.
    var now: Date = Date()
    /// The records' calendar (`CardRecordsModel.calendar`): days are named and picked in it.
    let calendar: Calendar

    @State private var selected: String?
    @State private var termSheet = false
    /// Bumped with each switch; the latest reads the new total out a moment later.
    @State private var switches = 0
    /// Bumped when it is time to read the new total out.
    @State private var announcement = 0
    /// The last category's refusal shows in the category note's place for a while (`refusalNote`).
    @State private var refusing = false
    /// Bumped with each refusal: only the latest puts the note back.
    @State private var refusals = 0
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(phase: Phase, span: Binding<SpendSpan>, placeholder: [SpendBar] = [], term: TermStartSheet.Term? = nil,
         setTermStart: @escaping (Date?) -> Void = { _ in }, pinned: String? = nil, comparing: Bool = false,
         toggleCategory: ((CardRecordKind) -> Bool)? = nil, counted: Set<CardRecordKind>? = nil, stale: Bool = false,
         staleSavedAt: Date? = nil, staleToday: Date? = nil, now: Date = Date(), calendar: Calendar) {
        self.phase = phase; _span = span; self.placeholder = placeholder; self.term = term
        self.setTermStart = setTermStart; self.pinned = pinned; self.comparing = comparing
        self.toggleCategory = toggleCategory; self.counted = counted; self.stale = stale
        self.staleSavedAt = staleSavedAt; self.staleToday = staleToday; self.now = now
        self.calendar = calendar
        _selected = State(initialValue:pinned)
    }

    private var text: SpendStatsText { SpendStatsText(theme:theme, calendar:calendar) }
    private var stats: SpendStats? { if case .loaded(let stats) = phase, stats.span == span { return stats }; return nil }
    private var loading: Bool { phase == .loading || (stats == nil && phase != .failed) }
    /// Nothing spent in the span on the categories counted, nor on those left out.
    private var empty: Bool { stats.map { $0.isEmpty && !nothingCounted } ?? false }
    /// Spent only on categories left out: the chart says so, over the capsules.
    private var nothingCounted: Bool { stats.map(SpendStatsText.nothingCounted) ?? false }
    /// The capsules: shown with nothing counted spent too, so a category left out can come back.
    private var shares: [SpendShare] { stats?.shares ?? [] }
    private var selectedBar: SpendBar? { selected.flatMap { id in stats?.bars.first { $0.id == id } } }

    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            SpendSpanSwitch(span:$span)
            if phase == .failed {
                failedLine.padding(.top,10)
            } else {
                if stale { staleLine }
                headline.padding(.top,stale ? 2 : 10)
                chart.padding(.top,20)
                if !shares.isEmpty {
                    // The capsules' 44pt rows put the first one's face 18 under the chart.
                    SpendShareFlow(shares:shares, counted:counted ?? Set(shares.filter(\.included).map(\.kind)),
                                   toggle:toggleCategory.map { switching($0) })
                        .padding(.top,12)
                    categoryNote.padding(.top,2)
                }
            }
            if span == .term, let term { termRow(term).padding(.top,8) }
            notes
            Text(text.footnote)
                .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal:false, vertical:true)
                .padding(.top,footnoteGap)
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .onChange(of:span) { _, _ in selected = nil }
        .onChange(of:announcement) { _, _ in
            if let stats { AccessibilityNotification.Announcement(text.spokenTotal(stats)).post() }
        }
        .onChange(of:pinned) { _, new in selected = new }
        .sheet(isPresented:$termSheet) {
            if let term { TermStartSheet(term:term, calendar:calendar, onDone:setTermStart) }
        }
    }

    /// Under the term's row, or straight under the category note: one paragraph with it.
    private var footnoteGap: CGFloat {
        if span == .term && term != nil { return 4 }
        let noted = stats.map { $0.coveredFrom != nil || $0.unsureDays > 0 } ?? false
        return !shares.isEmpty && phase != .failed && !noted ? 4 : 14
    }

    /// A capsule's tap: the host's switch, and the new total read out once it is worked out; a
    /// refusal is said on screen and read out.
    private func switching(_ toggle: @escaping (CardRecordKind) -> Bool) -> (CardRecordKind) -> Bool {
        { kind in
            let done = toggle(kind)
            if done { switched() } else { refused() }
            return done
        }
    }

    /// The new total is read out 0.6 s after a switch, once VoiceOver has said the capsule's new
    /// state; quick switches read only the last total.
    private func switched() {
        switches += 1
        let mine = switches
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(600))
            guard mine == switches else { return }
            announcement += 1
        }
    }

    /// The last category can't go: the note under the capsules says why for 2 s, crossfading
    /// (at once with Reduce Motion), and VoiceOver reads it out.
    private func refused() {
        refusals += 1
        let mine = refusals
        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.2)) { refusing = true }
        AccessibilityNotification.Announcement(SpendStatsText.lastCategoryNote).post()
        Task { @MainActor in
            try? await Task.sleep(for:.seconds(2))
            guard mine == refusals else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.2)) { refusing = false }
        }
    }

    /// The 电费 sentence, or for a while the refusal's in its place: both laid out, so the room is
    /// the taller one's and nothing below moves.
    private var categoryNote: some View {
        ZStack(alignment:.topLeading) {
            Text(SpendStatsText.categoryNote)
                .opacity(refusing ? 0 : 1)
                .accessibilityHidden(refusing)
            Text(SpendStatsText.lastCategoryNote)
                .opacity(refusing ? 1 : 0)
                .accessibilityHidden(!refusing)
                .accessibilityIdentifier("spendRefusalNote")
        }
        .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
        .fixedSize(horizontal:false, vertical:true)
        .frame(maxWidth:.infinity, alignment:.leading)
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
        } else if let bar = selectedBar, bar.unsure, bar.spent == .zero {
            Text(text.incompleteBar)
                .scaledFont(22, .semibold, design:theme.numberDesign, relativeTo:.title2)
                .foregroundStyle(Theme.ink)
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
            if let bar = selectedBar { parts = text.barLine(bar, average:stats.dailyAverage) }
            else if !nothingCounted { parts = text.averageLine(stats) }
        }
        return ZStack(alignment:.topLeading) {
            // While the comparison is read, a stand-in for it keeps its room, so nothing moves when it comes.
            if comparing, selectedBar == nil, !nothingCounted, let room = comparisonRoom {
                Self.join(room).hidden().accessibilityHidden(true)
            }
            if let parts {
                Self.join(parts)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration:0.25), value:parts)
            } else {
                Text(" ").accessibilityHidden(true)
            }
        }
        .scaledFont(13, relativeTo:.footnote)
        .monospacedDigit()
        .fixedSize(horizontal:false, vertical:true)
    }

    private static func join(_ parts: [SpendStatsText.Part]) -> Text {
        parts.reduce(Text(verbatim:"")) { line, part in
            let run = part.strong ? Text(part.text).fontWeight(.semibold).foregroundStyle(Theme.ink)
                                  : Text(part.text).foregroundStyle(Theme.ink2)
            return Text("\(line)\(run)")
        }
    }

    /// The average line with a comparison as long as the total, the widest it is likely to be.
    private var comparisonRoom: [SpendStatsText.Part]? {
        guard var stats, stats.span != .term, stats.versusPrevious == nil else { return nil }
        stats.versusPrevious = Money(fen:max(stats.total.fen, 10000))
        return text.averageLine(stats)
    }

    private var spokenHeadline: String {
        if loading { return text.totalLabel(span) + "，" + text.loading(span) }
        guard let stats else { return "" }
        if empty { return text.empty(stats.span) }
        // The chart's words are read next, on their own.
        if nothingCounted { return text.spokenAmount(stats) }
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
        if let stats, nothingCounted {
            // The words in the chart's place, as tall as it (an unseen chart holds the room, so the
            // page doesn't jump); taller only when large text needs it. Theme.ink2 is 清爽's
            // secondaryLabel.
            ZStack {
                SpendBarsChart(bars:stats.bars, span:span, look:.empty, average:nil, selected:.constant(nil), text:text)
                    .hidden()
                    .accessibilityHidden(true)
                Text(SpendStatsText.nothingCountedNote)
                    .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal:false, vertical:true)
                    .frame(maxWidth:.infinity)
                    .padding(.horizontal,24)
                    .accessibilityLabel(SpendStatsText.spokenNothingCounted)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("spendNothingCounted")
            }
        } else if let stats {
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

    // MARK: Lines

    /// Over everything under the span switch, as the stats and the list are both as last read.
    /// Gone at once when a pull reads the newest.
    private var staleLine: some View {
        HStack(alignment:.firstTextBaseline, spacing:5) {
            Image(systemName:"exclamationmark.arrow.circlepath").accessibilityHidden(true)
            Text(text.refreshFailed(savedAt:staleSavedAt, cachedToday:staleToday, now:now))
                .fixedSize(horizontal:false, vertical:true)
        }
        .scaledFont(13, relativeTo:.footnote)
        .foregroundStyle(Theme.ink2)
        .padding(.vertical,8)
        .accessibilityElement(children:.combine)
        .accessibilityIdentifier("recordsRefreshFailed")
        .transition(.identity)
    }

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
            if let from = stats.coveredFrom,
               from > (stats.bars.first?.days.first ?? stats.bars.first?.id ?? ""),
               let covered = text.coveredFrom(from) {
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
