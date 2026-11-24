//
//  CardRecordsLoader.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

/// Where 校园卡记录 reads its pages: the school session, or synthetic pages in a demo.
public struct CardRecordsSource: Sendable {
    /// Who is signed in now (`SchoolSession.personStamp()`).
    public var stamp: @Sendable () async -> Int
    /// One page, for the person signed in at `stamp` (`SchoolSession.cardHistoryPage`).
    public var page: @Sendable (CardHistoryQuery, Int) async throws -> CardRecordPage
    /// Nobody signed out and nobody else signed in since the stamp (`SchoolSession.isSamePerson`).
    public var samePerson: @Sendable (Int) async -> Bool
    /// The card session expired: renew it as home does; true when the card was read again.
    public var renew: @Sendable () async -> Bool
    /// The calendar its records are written in: the school's, or the sample's (`SampleData.calendar`).
    public var calendar: Calendar
    /// The person's records kept while the app runs: a visit shows them at once and reads only
    /// the newest range again. Nil: every visit reads from today.
    public var memory: CardRecordsMemory?
    /// Home's last read of the card's records (`HomeSnapshot.activity`), shown on a visit until
    /// the first pages come (`CardHistory.prefill(_:)`).
    public var prefill: (@MainActor @Sendable () -> CardActivity?)?

    public init(stamp: @escaping @Sendable () async -> Int,
                page: @escaping @Sendable (CardHistoryQuery, Int) async throws -> CardRecordPage,
                samePerson: @escaping @Sendable (Int) async -> Bool = { _ in true },
                renew: @escaping @Sendable () async -> Bool = { false },
                calendar: Calendar = SchoolCalendar.shanghai,
                memory: CardRecordsMemory? = nil,
                prefill: (@MainActor @Sendable () -> CardActivity?)? = nil) {
        self.stamp = stamp; self.page = page; self.samePerson = samePerson; self.renew = renew
        self.calendar = calendar; self.memory = memory; self.prefill = prefill
    }
}

/// What 校园卡记录 shows.
public struct CardRecordsState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// The first read is running and nothing is shown yet.
        case loading
        /// The first read failed: the line, and the app's own records only.
        case failed
        case loaded
    }
    public var phase = Phase.loading
    public var history: CardHistory?
    public var loadingMore = false
    /// The last 「load more」 failed: the footer offers to try again. The rows stay.
    public var moreFailed = false
    /// A read from today is running (first visit, pull): no older page is asked for meanwhile.
    public var reloading = false
    /// Reads from today that came in: the list's end is renewed with each, so one already in
    /// view asks for older pages for the new list.
    public var reloads = 0
    /// A visit showed the records kept in memory and could not read the newest range again: the
    /// list is as it was when last read. Cleared by the next read from today that comes in.
    public var refreshFailed = false
    public init() {}
}

/// 校园卡记录's reads: from today on a visit or pull, older pages as the list's end appears.
/// Nothing is written anywhere. With the source's `memory`, a visit shows the records kept from
/// an earlier visit at once (on the same day), reads only the newest range again and joins it
/// onto them; a pull always reads from today afresh. Without kept records, home's last read
/// (`prefill`) shows until the first page comes. A read that returns after a newer read from
/// today started is dropped, and so is an older page read for a list that has been replaced
/// meanwhile.
@MainActor public final class CardRecordsLoader {
    public private(set) var state = CardRecordsState() {
        didSet {
            guard state != oldValue else { return }
            if state.phase == .loaded, !state.reloading, let history = state.history {
                source.memory?.keep(history, stamp: stamp)
            }
            changed?(state)
        }
    }
    /// Called on every change of `state`.
    public var changed: ((CardRecordsState) -> Void)?
    private let source: CardRecordsSource
    private let now: () -> Date
    /// Who was signed in when the shown list was read from today.
    private var stamp = 0
    /// Bumped by `reload()`: a read that returns afterwards is dropped.
    private var generation = 0
    /// The oldest day (`yyyyMMdd`) the records page's stats need: after a read from today or an
    /// older page, older pages are read on until the list holds it, ends, or a read fails.
    public private(set) var target: String?

    public init(source: CardRecordsSource, now: @escaping () -> Date = Date.init) {
        self.source = source; self.now = now
    }

    /// The calendar the records' days and times are read in (`CardRecordsSource.calendar`).
    public var calendar: Calendar { source.calendar }

    /// From today again (first visit, pull).
    public func reload() async {
        generation += 1
        let mine = generation
        // The page's first read: it may start from what is kept, or from home's last records.
        let visit = mine == 1
        state.reloading = true
        let stamp = await source.stamp()
        guard mine == generation else { return }
        var start = CardHistory(now: now(), calendar: source.calendar)
        let load: CardHistory.Load
        if visit, let kept = source.memory?.history(for: stamp) {
            guard let fresh = await rejoin(kept, start: start, stamp: stamp, mine: mine) else { return }
            load = fresh
        } else {
            if visit, state.phase == .loading, let activity = source.prefill?() {
                start.prefill(activity)
                if start.readThrough != nil {
                    var shown = state
                    shown.history = start
                    shown.phase = .loaded
                    state = shown
                }
            }
            load = await Self.read(start, source: source, stamp: stamp)
        }
        guard mine == generation else { return }
        self.stamp = stamp
        var next = state
        next.reloading = false
        next.loadingMore = false
        next.refreshFailed = false
        next.reloads += 1
        // Home's records it showed meanwhile (`prefill`) are not a read: nothing of its own, and
        // the read failed.
        if load.history.readRecords.isEmpty, load.failure != nil {
            next.history = nil; next.phase = .failed; next.moreFailed = false
        } else {
            next.history = load.history; next.phase = .loaded; next.moreFailed = load.failure != nil
        }
        state = next
        if next.phase == .loaded, load.failure == nil, needsMore(load.history) {
            Task { [weak self] in await self?.loadMore() }
        }
    }

    /// A visit with records kept: shows them at once when they were read today, reads the newest
    /// range again and joins it onto them, then reads on back to `target` if need be. A failure
    /// leaves the kept records shown, if they were (`refreshFailed`). Otherwise (kept records
    /// too old to join, or a failure with nothing shown) the read comes back for the caller to
    /// take as a read from today; nil when done.
    private func rejoin(_ kept: CardHistory, start: CardHistory, stamp: Int, mine: Int) async -> CardHistory.Load? {
        let shown = kept.today == start.today
        if shown {
            self.stamp = stamp
            var next = state
            next.history = kept
            next.phase = .loaded
            state = next
        }
        let load = await Self.read(start, source: source, stamp: stamp, firstRange: true)
        guard mine == generation else { return nil }
        if load.failure != nil {
            guard shown else { return load }
            var next = state
            next.reloading = false
            next.refreshFailed = true
            next.reloads += 1
            state = next
            return nil
        }
        guard let joined = load.history.joined(earlier: kept) else { return load }
        self.stamp = stamp
        var next = state
        next.history = joined
        next.phase = .loaded
        next.reloading = false
        next.loadingMore = false
        next.moreFailed = false
        next.refreshFailed = false
        next.reloads += 1
        state = next
        if needsMore(joined), !joined.reachedEnd {
            Task { [weak self] in await self?.loadMore() }
        }
        return nil
    }

    /// Reads back until the list holds `day` (`yyyyMMdd`), its end, or a failure; from then on
    /// every read goes on back to it (see `target`). Returns at once while another read runs:
    /// that one goes on to `day`.
    public func read(through day: String) async {
        target = day
        await loadMore()
    }

    /// Moves `target` to `day` without reading: a read running stops once the list holds it, and
    /// later reads from today go back to it only. A span that needs fewer days than before.
    public func setTarget(_ day: String?) {
        target = day
    }

    /// The list does not hold `target` yet.
    private func needsMore(_ history: CardHistory) -> Bool {
        guard let target else { return false }
        return !history.hasRead(through: target)
    }

    /// Older records: when the list's end appears, or 「点这里再试」; then on back to `target`.
    public func loadMore() async {
        guard state.phase == .loaded, !state.reloading, !state.loadingMore,
              var current = state.history, !current.reachedEnd else { return }
        let mine = generation
        state.loadingMore = true
        state.moreFailed = false
        while true {
            let load = await Self.read(current, source: source, stamp: stamp)
            // A read from today started meanwhile: it owns the list (and `loadingMore`) now.
            guard mine == generation, !state.reloading, state.history == current else { return }
            if load.failure != nil, !(await source.samePerson(stamp)) {
                // Signed out, or someone else signed in: their rows go, and the list is read again
                // for whoever is signed in now (nothing, signed out).
                guard mine == generation, !state.reloading else { return }
                source.memory?.clear()
                state = CardRecordsState()
                await reload()
                return
            }
            let more = load.failure == nil && !load.history.reachedEnd && needsMore(load.history)
            var next = state
            next.history = load.history
            next.moreFailed = load.failure != nil
            next.loadingMore = more
            state = next
            guard more else { return }
            current = load.history
        }
    }

    /// Pages from `history` on. A failure that says the card session is gone has it renewed
    /// once, as home renews it, for the person the list was read for only, and the read goes on
    /// from the same page. Nothing is renewed when the network failed or the school refused for
    /// another reason. `firstRange`: on until the first range is read to its end
    /// (`CardHistory.loadFirstRange`) rather than until a page brings rows.
    nonisolated static func read(_ history: CardHistory, source: CardRecordsSource, stamp: Int,
                                 firstRange: Bool = false) async -> CardHistory.Load {
        let page = source.page
        func load(_ history: CardHistory) async -> CardHistory.Load {
            if firstRange { return await CardHistory.loadFirstRange(history) { query in try await page(query, stamp) } }
            return await CardHistory.loadMore(history) { query in try await page(query, stamp) }
        }
        let first = await load(history)
        guard let failure = first.failure, sessionGone(failure),
              await source.samePerson(stamp), await source.renew() else { return first }
        return await load(first.history)
    }

    /// getRecordList does not validate the session: an expired one comes back as the school's
    /// code -1 or as an empty reply (`badRequest`), besides `sessionExpired` itself.
    nonisolated static func sessionGone(_ failure: ServiceError) -> Bool {
        switch failure {
        case .sessionExpired, .badRequest: return true
        case .rejected(_, let code, _): return code == "-1"
        default: return false
        }
    }
}
