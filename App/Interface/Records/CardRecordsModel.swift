//
//  CardRecordsModel.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation
import Core

extension CardRecordsSource {
    /// `campus`'s school session (the live one, or a sample's, which reads nothing): pages for
    /// the person signed in when the list was read from today.
    @MainActor static func school(_ campus: CampusModel) -> CardRecordsSource {
        let session = campus.schoolSession
        return CardRecordsSource(stamp:{ await session.personStamp() },
                                 page:{ query, stamp in try await session.cardHistoryPage(query, since:stamp) },
                                 samePerson:{ await session.isSamePerson(since:$0) },
                                 renew:{ [weak campus] in await campus?.renewCardSession() ?? false })
    }
}

/// 校园卡记录's state for SwiftUI, over Core's `CardRecordsLoader`, and the page's spending
/// stats (`SpendStats`) for the span chosen. The records are not stored: every visit (and every
/// pull) starts from today, and reads back as far as the stats need. The span and the start day
/// set for this term are kept in the graph's preferences once `bind(_:)` gives them.
@MainActor final class CardRecordsModel: ObservableObject {
    @Published private(set) var state = CardRecordsState()
    /// The stats' span: kept under `SpendSpan.storeKey`; the records are read back far enough for it.
    @Published var statsSpan: SpendSpan = .week {
        didSet {
            guard statsSpan != oldValue else { return }
            preferences?.set(statsSpan.rawValue, forKey:SpendSpan.storeKey)
            updateStats()
        }
    }
    /// The stats for `statsSpan`; nil while the span's records are read (`statsLoading`) or when
    /// they could not be (`statsFailed`). Given as soon as the span itself is read; its
    /// `versusPrevious` stays nil while the period before it is read (`comparisonLoading`).
    @Published private(set) var stats: SpendStats?
    @Published private(set) var statsLoading = true
    /// The stats are shown and the period before the span is still being read for the
    /// comparison (7 / 30 days only): `stats.versusPrevious` comes when it is. False once it
    /// came, or the read stopped (`moreFailed`: no comparison).
    @Published private(set) var comparisonLoading = false
    /// The span's records could not be read (the first read failed, or an older page did).
    @Published private(set) var statsFailed = false
    /// The start day the user set for this term, whether or not it still counts.
    @Published private(set) var customTermStart: Date?

    private let loader: CardRecordsLoader
    private let now: () -> Date
    private var preferences: (any PreferenceStorage)?

    init(source: CardRecordsSource, preferences: (any PreferenceStorage)? = nil, now: @escaping () -> Date = Date.init) {
        loader = CardRecordsLoader(source:source, now:now)
        self.now = now
        loader.changed = { [weak self] in
            self?.state = $0
            self?.updateStats()
        }
        if let preferences { bind(preferences) }
    }

    var phase: CardRecordsState.Phase { state.phase }
    var history: CardHistory? { state.history }
    var loadingMore: Bool { state.loadingMore }
    var moreFailed: Bool { state.moreFailed }
    var reloads: Int { state.reloads }
    /// The calendar the records are read in (the school's, or the sample's).
    var calendar: Calendar { loader.calendar }

    /// From today again (first visit, pull), then back as far as the stats need.
    func reload() async { await loader.reload() }
    /// Older records: when the list's end appears, or 「点这里再试」.
    func loadMore() async { await loader.loadMore() }

    // MARK: Stats

    /// The preferences the span and the term's start day are kept in (the graph's
    /// `CampusServices.defaults`: a sample's stay in the sample). Until then nothing is kept.
    func bind(_ preferences: any PreferenceStorage) {
        guard self.preferences !== preferences else { return }
        self.preferences = preferences
        customTermStart = TermStartStore(preferences:preferences, calendar:calendar).custom
        if let raw = preferences.object(forKey:SpendSpan.storeKey) as? String, let span = SpendSpan(rawValue:raw),
           span != statsSpan {
            statsSpan = span
        } else {
            updateStats()
        }
    }

    /// This term's first day in effect: the one set while it counts, otherwise 3月1日 / 9月1日.
    var termStart: Date { TermStart.start(today:now(), custom:customTermStart, calendar:calendar) }
    /// The default rule's day (「用回 9月1日」).
    var defaultTermStart: Date { TermStart.defaultStart(today:now(), calendar:calendar) }
    /// A day the user set counts now.
    var termStartIsCustom: Bool {
        customTermStart.map { TermStart.isActive(custom:$0, today:now(), calendar:calendar) } ?? false
    }
    /// Days the start can be set to: the earliest day this term takes through today.
    var termStartRange: ClosedRange<Date> { TermStart.pickerRange(today:now(), calendar:calendar) }

    /// Sets this term's start day. A day that would not count today (after today, or another
    /// term's) is refused: nothing is kept, and false comes back.
    @discardableResult
    func setTermStart(_ day: Date) -> Bool {
        let kept = calendar.startOfDay(for:day)
        guard TermStart.isActive(custom:kept, today:now(), calendar:calendar) else { return false }
        customTermStart = kept
        if let preferences { TermStartStore(preferences:preferences, calendar:calendar).set(kept) }
        updateStats()
        return true
    }

    /// Back to the default start day.
    func resetTermStart() {
        customTermStart = nil
        if let preferences { TermStartStore(preferences:preferences, calendar:calendar).clear() }
        updateStats()
    }

    /// Works the stats out again from the records read, and has older pages read when the span
    /// needs them.
    private func updateStats() {
        switch state.phase {
        case .loading:
            set(stats:nil, loading:true, failed:false, comparing:false)
        case .failed:
            set(stats:nil, loading:false, failed:true, comparing:false)
        case .loaded:
            guard let history = state.history else { set(stats:nil, loading:false, failed:true, comparing:false); return }
            let start = termStart
            let first = SpendStats.firstDayNeeded(span:statsSpan, today:now(), termStart:start, calendar:calendar)
            let made = SpendStats.make(span:statsSpan, history:history, termStart:start, calendar:calendar)
            // Always the span's day, a nearer one too: a read running stops there, and a pull
            // reads back to it only.
            let moved = loader.target != first
            loader.setTarget(first)
            if history.hasRead(through:first) || state.moreFailed {
                set(stats:made, loading:false, failed:made == nil, comparing:false)
                return
            }
            // The span itself is read (`made`): its stats show, and the comparison follows once the
            // period before it is.
            set(stats:made, loading:made == nil, failed:false, comparing:made != nil)
            if moved || (!state.loadingMore && !state.reloading) {
                Task { [weak self] in await self?.loader.loadMore() }
            }
        }
    }

    private func set(stats: SpendStats?, loading: Bool, failed: Bool, comparing: Bool) {
        if self.stats != stats { self.stats = stats }
        if statsLoading != loading { statsLoading = loading }
        if statsFailed != failed { statsFailed = failed }
        if comparisonLoading != comparing { comparisonLoading = comparing }
    }
}
