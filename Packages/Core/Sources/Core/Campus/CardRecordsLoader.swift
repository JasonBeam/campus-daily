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
    /// Optional app-private disk cache (`CardHistoryDiskCoordinator`): nil in sample mode and
    /// tests that want memory-only behavior.
    public var diskCache: (any CardHistoryCaching)?
    /// Home's last read of the card's records (`HomeSnapshot.activity`), shown on a visit until
    /// the first pages come (`CardHistory.prefill(_:)`).
    public var prefill: (@MainActor @Sendable () -> CardActivity?)?

    public init(stamp: @escaping @Sendable () async -> Int,
                page: @escaping @Sendable (CardHistoryQuery, Int) async throws -> CardRecordPage,
                samePerson: @escaping @Sendable (Int) async -> Bool = { _ in true },
                renew: @escaping @Sendable () async -> Bool = { false },
                calendar: Calendar = SchoolCalendar.shanghai,
                memory: CardRecordsMemory? = nil,
                diskCache: (any CardHistoryCaching)? = nil,
                prefill: (@MainActor @Sendable () -> CardActivity?)? = nil) {
        self.stamp = stamp; self.page = page; self.samePerson = samePerson; self.renew = renew
        self.calendar = calendar; self.memory = memory; self.diskCache = diskCache; self.prefill = prefill
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
    /// A visit showed cached records (from memory or disk) and could not read the newest range
    /// again: the list is as it was when last read. Cleared by the next read from today that comes in.
    public var refreshFailed = false
    /// When the shown cached records were last written to memory/disk.
    public var cachedSavedAt: Date?
    /// When the newest 14-day range of the shown records was last successfully read from the
    /// school (not bumped when `loadMore()` reads older pages). Used for the same-day "as of HH:mm"
    /// hint while `refreshFailed` is true.
    public var cachedLatestReadAt: Date?
    public init() {}
}

/// 校园卡记录's reads: from today on a visit or pull, older pages as the list's end appears.
/// With `memory` and/or `diskCache`, a first visit hydrates cached records at once, reads only
/// the newest 14-day range and joins it onto them (strictly requiring real date overlap via
/// `CardHistory.joined(earlier:)`); a pull always reads from today afresh and overwrites the
/// cache. Without cached records, home's last read (`prefill`) shows until the first page comes.
/// A read that returns after a newer read from today started is dropped, and so is an older page
/// read for a list that has been replaced meanwhile.
@MainActor public final class CardRecordsLoader {
    public private(set) var state = CardRecordsState() {
        didSet {
            guard state != oldValue else { return }
            if state.phase == .loaded, !state.reloading, !state.refreshFailed, let history = state.history {
                source.memory?.keep(history, stamp: stamp,
                                    savedAt: state.cachedSavedAt,
                                    latestReadAt: state.cachedLatestReadAt ?? state.cachedSavedAt)
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
        // The page's first read: it may start from what is kept (memory or disk), or from home's last records.
        let visit = mine == 1
        state.reloading = true
        let stamp = await source.stamp()
        guard mine == generation else { return }
        let readNow = now()
        var start = CardHistory(now: readNow, calendar: source.calendar)
        let load: CardHistory.Load
        var keptEntry: CachedCardHistory? = visit ? source.memory?.entry(for: stamp, now: readNow) : nil
        if visit, keptEntry == nil, let disk = source.diskCache {
            let source = source
            let loaded = await disk.load(now: readNow, calendar: source.calendar,
                                         samePerson: { await source.samePerson(stamp) })
            let stillSame = loaded != nil ? await source.samePerson(stamp) : false
            guard mine == generation else { return }
            if let loaded, stillSame {
                keptEntry = loaded
                source.memory?.keep(loaded.history, stamp: stamp,
                                    savedAt: loaded.savedAt,
                                    latestReadAt: loaded.latestReadAt ?? loaded.savedAt)
            }
        }
        if visit, let kept = keptEntry {
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
        // Final delivery boundary: re-verify both person ownership and page generation after the
        // last await so a late or partial read for a previous account never publishes or overwrites
        // the current account's state.
        let stillSame = await source.samePerson(stamp)
        guard mine == generation else { return }
        if !stillSame {
            source.memory?.clear()
            if load.history.readRecords.isEmpty, load.failure != nil {
                self.stamp = stamp
                var next = state
                next.reloading = false
                next.loadingMore = false
                next.refreshFailed = false
                next.cachedSavedAt = nil
                next.cachedLatestReadAt = nil
                next.reloads += 1
                next.history = nil
                next.phase = .failed
                next.moreFailed = false
                state = next
            } else {
                state = CardRecordsState()
            }
            return
        }
        // Home's records it showed meanwhile (`prefill`) are not a read: nothing of its own, and
        // the read failed. On a pull-to-refresh while offline, keep the same person's already
        // loaded real history with `refreshFailed = true` instead of blanking the page.
        if load.history.readRecords.isEmpty, load.failure != nil {
            if !visit, let existing = state.history, existing.holdsFirstRange,
               self.stamp == stamp {
                var next = state
                next.reloading = false
                next.loadingMore = false
                next.refreshFailed = true
                next.reloads += 1
                state = next
                return
            }
            self.stamp = stamp
            var next = state
            next.reloading = false
            next.loadingMore = false
            next.refreshFailed = false
            next.cachedSavedAt = nil
            next.cachedLatestReadAt = nil
            next.reloads += 1
            next.history = nil
            next.phase = .failed
            next.moreFailed = false
            state = next
            return
        }
        let readCompletedAt = load.history.holdsFirstRange ? now() : nil
        self.stamp = stamp
        var next = state
        next.reloading = false
        next.loadingMore = false
        next.refreshFailed = false
        next.cachedSavedAt = readCompletedAt
        next.cachedLatestReadAt = readCompletedAt
        next.reloads += 1
        next.history = load.history
        next.phase = .loaded
        next.moreFailed = load.failure != nil
        state = next
        if let readCompletedAt, load.history.holdsFirstRange {
            await persist(load.history, stamp: stamp,
                          savedAt: readCompletedAt, latestReadAt: readCompletedAt, mine: mine)
        }
        if mine == generation, next.phase == .loaded, load.failure == nil, needsMore(load.history) {
            Task { [weak self] in await self?.loadMore() }
        }
    }

    /// A visit with cached records: shows them at once (same day or earlier day), reads the
    /// newest 14-day range again and joins it onto them via real date overlap, then reads on back
    /// to `target` if need be. A failure leaves the cached records shown with `refreshFailed` and
    /// their original `latestReadAt`/`savedAt`. Otherwise (cached records too old to join / gapped,
    /// or no overlap) the read comes back for the caller to take as a fresh read from today; nil when done.
    private func rejoin(_ kept: CachedCardHistory, start: CardHistory, stamp: Int, mine: Int) async -> CardHistory.Load? {
        let canShow = kept.history.today <= start.today
        let sameBeforeShow = canShow ? await source.samePerson(stamp) : false
        guard mine == generation else { return nil }
        let shown = canShow && sameBeforeShow
        if shown {
            self.stamp = stamp
            var next = state
            next.history = kept.history
            next.cachedSavedAt = kept.savedAt
            next.cachedLatestReadAt = kept.latestReadAt ?? kept.savedAt
            next.phase = .loaded
            state = next
        }
        let load = await Self.read(start, source: source, stamp: stamp, firstRange: true)
        let stillSame = await source.samePerson(stamp)
        guard mine == generation else { return nil }
        if !stillSame {
            source.memory?.clear()
            state = CardRecordsState()
            return nil
        }
        if load.failure != nil {
            guard shown else { return load }
            var next = state
            next.reloading = false
            next.refreshFailed = true
            next.cachedSavedAt = kept.savedAt
            next.cachedLatestReadAt = kept.latestReadAt ?? kept.savedAt
            next.reloads += 1
            state = next
            return nil
        }
        guard let joined = load.history.joined(earlier: kept.history) else { return load }
        let readCompletedAt = now()
        self.stamp = stamp
        var next = state
        next.history = joined
        next.cachedSavedAt = readCompletedAt
        next.cachedLatestReadAt = readCompletedAt
        next.phase = .loaded
        next.reloading = false
        next.loadingMore = false
        next.moreFailed = false
        next.refreshFailed = false
        next.reloads += 1
        state = next
        await persist(joined, stamp: stamp,
                      savedAt: readCompletedAt, latestReadAt: readCompletedAt, mine: mine)
        if mine == generation, needsMore(joined), !joined.reachedEnd {
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
        let startingReadFrom = current.readFrom
        let startingReachedEnd = current.reachedEnd
        var latestToPersist: CardHistory?
        state.loadingMore = true
        state.moreFailed = false
        while true {
            let load = await Self.read(current, source: source, stamp: stamp)
            // Fast check before awaiting person ownership.
            guard mine == generation, !state.reloading, state.history == current else { return }
            let stillSame = await source.samePerson(stamp)
            // Final delivery boundary after the last await: verify both page generation and
            // person ownership before touching memory or UI state (even when partial rows arrived).
            guard mine == generation, !state.reloading, state.history == current else { return }
            if !stillSame {
                // Signed out, or someone else signed in: their rows go, and the list is read again
                // for whoever is signed in now (nothing, signed out).
                source.memory?.clear()
                state = CardRecordsState()
                await reload()
                return
            }
            if load.history.holdsFirstRange,
               (load.history.readFrom != startingReadFrom || load.history.reachedEnd != startingReachedEnd) {
                latestToPersist = load.history
            }
            let more = load.failure == nil && !load.history.reachedEnd && needsMore(load.history)
            let fileSavedAt = (!more && latestToPersist != nil && !state.refreshFailed) ? now() : state.cachedSavedAt
            let latestReadAt = state.cachedLatestReadAt ?? state.cachedSavedAt
            var next = state
            next.history = load.history
            next.moreFailed = load.failure != nil
            next.loadingMore = more
            // Reading older pages updates the file write time (`cachedSavedAt`) without bumping
            // `cachedLatestReadAt` (when the newest 14-day range was actually read from school).
            if !state.refreshFailed {
                next.cachedSavedAt = fileSavedAt
                next.cachedLatestReadAt = latestReadAt
            }
            state = next
            guard more else {
                if let latestToPersist, !state.refreshFailed {
                    let writeTime = fileSavedAt ?? now()
                    await persist(latestToPersist, stamp: stamp,
                                  savedAt: writeTime,
                                  latestReadAt: latestReadAt ?? writeTime,
                                  mine: mine)
                }
                return
            }
            current = load.history
        }
    }

    private func persist(_ history: CardHistory, stamp: Int, savedAt: Date, latestReadAt: Date, mine: Int) async {
        guard mine == generation, history.holdsFirstRange, let disk = source.diskCache else { return }
        let source = source
        await disk.save(history, savedAt: savedAt, latestReadAt: latestReadAt,
                        samePerson: { await source.samePerson(stamp) })
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
