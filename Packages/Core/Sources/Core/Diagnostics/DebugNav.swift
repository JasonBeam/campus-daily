import Foundation

/// `nav.open` lines. Whatever routes (a tap that goes through code, a widget link, a
/// notification, a Shortcut, the page raising itself, a page put back) says why with `from`
/// just before, naming the pages it will open; each of those pages then logs that entry once
/// when it appears, and a page nothing was said for logs its own default (a plain tap). An
/// entry older than `pendingLifetime` is not used. With no pages named, the next page to open
/// takes it. `unlessPending`: only when no reason was given for those pages already (the page
/// raising itself after a tap or a Shortcut asked for it keeps the first reason).
/// Every line goes to the log whether or not it is on yet: at launch it holds them until the
/// install is known and keeps them on TestFlight only. What waits here is a few entries, dropped
/// at the next call once older than `pendingLifetime`.
public final class DebugNav: @unchecked Sendable {
    // @unchecked: `pending` is touched only under `lock`.
    public static let pendingLifetime: TimeInterval = 3
    private let log: any DebugLogSink
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private struct Pending { var entry: DebugEntry; var pages: Set<DebugPage>?; var at: Date }
    /// Oldest first.
    private var pending: [Pending] = []

    public init(log: any DebugLogSink, now: @escaping @Sendable () -> Date = Date.init) {
        self.log = log; self.now = now
    }

    public func from(_ entry: DebugEntry, to pages: Set<DebugPage>? = nil, unlessPending: Bool = false) {
        let at = now()
        lock.withLock {
            drop(before: at)
            if unlessPending, pending.contains(where: { p in p.pages.map { named in pages.map { !named.isDisjoint(with: $0) } ?? true } ?? true }) {
                return
            }
            // A newer reason for a page replaces an older one still waiting for it.
            if let pages {
                for i in pending.indices { pending[i].pages?.subtract(pages) }
                pending.removeAll { $0.pages?.isEmpty ?? false }
            }
            pending.append(Pending(entry: entry, pages: pages, at: at))
        }
    }

    public func opened(_ page: DebugPage, default entry: DebugEntry) {
        let at = now()
        let used: DebugEntry = lock.withLock {
            drop(before: at)
            // The newest reason that names this page, or names none.
            guard let i = pending.lastIndex(where: { $0.pages?.contains(page) ?? true }) else { return entry }
            let p = pending[i]
            if var pages = p.pages {
                pages.remove(page)
                if pages.isEmpty { pending.remove(at: i) } else { pending[i].pages = pages }
            } else {
                pending.remove(at: i)
            }
            return p.entry
        }
        log.record(.navOpen(page, from: used))
    }

    /// Under `lock`: reasons too old to be this page's.
    private func drop(before at: Date) {
        pending.removeAll { at.timeIntervalSince($0.at) > Self.pendingLifetime || at < $0.at }
    }
}
