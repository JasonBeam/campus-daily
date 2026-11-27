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
    private var kept: (history: CardHistory, stamp: Int, savedAt: Date?)?

    public init() {}

    /// The records kept for the person signed in at `stamp` (`SchoolSession.personStamp()`); nil
    /// when none, or when they were someone else's.
    public func history(for stamp: Int) -> CardHistory? {
        guard let kept, kept.stamp == stamp else { return nil }
        return kept.history
    }

    /// The records and save timestamp kept for `stamp`, or nil when none or another person's.
    public func entry(for stamp: Int) -> CachedCardHistory? {
        guard let kept, kept.stamp == stamp else { return nil }
        return CachedCardHistory(history: kept.history, savedAt: kept.savedAt)
    }

    /// Keeps `history`, read for the person signed in at `stamp`, once its first range is read
    /// to its end; a read that has not got that far leaves what is kept alone.
    public func keep(_ history: CardHistory, stamp: Int, savedAt: Date? = nil) {
        guard history.holdsFirstRange else { return }
        kept = (history, stamp, savedAt)
    }

    public func clear() { kept = nil }

    public var isEmpty: Bool { kept == nil }
}
