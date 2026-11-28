//
//  CardRecordsMemory.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import Foundation

/// 校园卡记录's records kept in memory for one person while the app runs, so a page opened again
/// reads only the newest range and joins it onto them (`CardHistory.joined(earlier:)`). Never
/// written anywhere. Its owner (`CampusModel`) makes a new one for every change of person and
/// clears the old one.
@MainActor public final class CardRecordsMemory {
    private var kept: (history: CardHistory, stamp: Int, savedAt: Date?, latestReadAt: Date?)?

    public init() {}

    /// The records kept for the person signed in at `stamp` (`SchoolSession.personStamp()`); nil
    /// when none, when they were someone else's, or when expired (>30d) / outside the 210-day window.
    public func history(for stamp: Int,
                        now: Date = Date(),
                        maxAge: TimeInterval = CardHistory.maxCacheAge,
                        maxDays: Int = CardHistory.maxCacheDays) -> CardHistory? {
        entry(for: stamp, now: now, maxAge: maxAge, maxDays: maxDays)?.history
    }

    /// The records and timestamps kept for `stamp`, or nil when none, another person's, expired
    /// (>30 days since either `savedAt` or `latestReadAt`), or wholly outside the 210-day window
    /// anchored on `now`.
    public func entry(for stamp: Int,
                      now: Date = Date(),
                      maxAge: TimeInterval = CardHistory.maxCacheAge,
                      maxDays: Int = CardHistory.maxCacheDays) -> CachedCardHistory? {
        guard let kept, kept.stamp == stamp else { return nil }
        if let savedAt = kept.savedAt, now.timeIntervalSince(savedAt) > maxAge {
            self.kept = nil
            return nil
        }
        if let latest = kept.latestReadAt ?? kept.savedAt, now.timeIntervalSince(latest) > maxAge {
            self.kept = nil
            return nil
        }
        guard let trimmed = kept.history.trimmedToCacheWindow(now: now, maxDays: maxDays) else {
            self.kept = nil
            return nil
        }
        return CachedCardHistory(history: trimmed,
                                 savedAt: kept.savedAt,
                                 latestReadAt: kept.latestReadAt ?? kept.savedAt)
    }

    /// Keeps `history`, read for the person signed in at `stamp`, once its first range is read
    /// to its end; a read that has not got that far leaves what is kept alone.
    public func keep(_ history: CardHistory, stamp: Int, savedAt: Date? = nil, latestReadAt: Date? = nil) {
        guard history.holdsFirstRange else { return }
        kept = (history, stamp, savedAt, latestReadAt ?? savedAt)
    }

    public func clear() { kept = nil }

    public var isEmpty: Bool { kept == nil }
}
