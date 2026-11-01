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

    public init(stamp: @escaping @Sendable () async -> Int,
                page: @escaping @Sendable (CardHistoryQuery, Int) async throws -> CardRecordPage,
                samePerson: @escaping @Sendable (Int) async -> Bool = { _ in true },
                renew: @escaping @Sendable () async -> Bool = { false }) {
        self.stamp = stamp; self.page = page; self.samePerson = samePerson; self.renew = renew
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
    public init() {}
}

/// 校园卡记录's reads: from today on a visit or pull, older pages as the list's end appears.
/// Nothing is stored. A read that returns after a newer read from today started is dropped,
/// and so is an older page read for a list that has been replaced meanwhile.
@MainActor public final class CardRecordsLoader {
    public private(set) var state = CardRecordsState() {
        didSet { if state != oldValue { changed?(state) } }
    }
    /// Called on every change of `state`.
    public var changed: ((CardRecordsState) -> Void)?
    private let source: CardRecordsSource
    private let now: () -> Date
    /// Who was signed in when the shown list was read from today.
    private var stamp = 0
    /// Bumped by `reload()`: a read that returns afterwards is dropped.
    private var generation = 0

    public init(source: CardRecordsSource, now: @escaping () -> Date = Date.init) {
        self.source = source; self.now = now
    }

    /// From today again (first visit, pull).
    public func reload() async {
        generation += 1
        let mine = generation
        state.reloading = true
        let stamp = await source.stamp()
        let load = await Self.read(CardHistory(now: now()), source: source, stamp: stamp)
        guard mine == generation else { return }
        self.stamp = stamp
        var next = state
        next.reloading = false
        next.loadingMore = false
        next.reloads += 1
        if load.history.records.isEmpty, load.failure != nil {
            next.history = nil; next.phase = .failed; next.moreFailed = false
        } else {
            next.history = load.history; next.phase = .loaded; next.moreFailed = load.failure != nil
        }
        state = next
    }

    /// Older records: when the list's end appears, or 「点这里再试」.
    public func loadMore() async {
        guard state.phase == .loaded, !state.reloading, !state.loadingMore,
              let current = state.history, !current.reachedEnd else { return }
        let mine = generation
        state.loadingMore = true
        state.moreFailed = false
        let load = await Self.read(current, source: source, stamp: stamp)
        // A read from today started meanwhile: it owns the list (and `loadingMore`) now.
        guard mine == generation, !state.reloading, state.history == current else { return }
        if load.failure != nil, !(await source.samePerson(stamp)) {
            // Signed out, or someone else signed in: their rows go, and the list is read again
            // for whoever is signed in now (nothing, signed out).
            guard mine == generation, !state.reloading else { return }
            state = CardRecordsState()
            await reload()
            return
        }
        var next = state
        next.history = load.history
        next.moreFailed = load.failure != nil
        next.loadingMore = false
        state = next
    }

    /// Pages from `history` on. A failure that says the card session is gone has it renewed
    /// once, as home renews it, for the person the list was read for only, and the read goes on
    /// from the same page. Nothing is renewed when the network failed or the school refused for
    /// another reason.
    nonisolated static func read(_ history: CardHistory, source: CardRecordsSource, stamp: Int) async -> CardHistory.Load {
        let page = source.page
        let load = await CardHistory.loadMore(history) { query in try await page(query, stamp) }
        guard let failure = load.failure, sessionGone(failure),
              await source.samePerson(stamp), await source.renew() else { return load }
        return await CardHistory.loadMore(load.history) { query in try await page(query, stamp) }
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
