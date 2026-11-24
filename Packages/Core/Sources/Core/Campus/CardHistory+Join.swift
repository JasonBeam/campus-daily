//
//  CardHistory+Join.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import Foundation

/// A read from today that need not start empty: joined onto an earlier read of the same
/// person's records (kept in memory while the app runs), or showing home's last records until its
/// own pages come.
extension CardHistory {
    /// Its first range (today and the `rangeDays - 1` days before) is read to its end.
    public var holdsFirstRange: Bool { readFrom != nil }

    /// This read's first range with the older days of `earlier`, an earlier read of the same
    /// person's records: the days this read holds are its own, the older ones `earlier`'s (its
    /// records, unsure days and where it stopped), so the list goes on back from where `earlier`
    /// was. Nil when they can't be joined: this read has not just finished its first range, or
    /// `earlier` holds no finished range older than it, or `earlier`'s today is not among the
    /// days read again here (its last days may have had records since, so they are never kept).
    public func joined(earlier: CardHistory) -> CardHistory? {
        guard let freshFrom = readFrom, current.isEmpty, !reachedEnd,
              let earlierFrom = earlier.readFrom, earlierFrom < freshFrom else { return nil }
        let todayID = SchoolCalendar.dayString(today, calendar: calendar)
        let earlierToday = SchoolCalendar.dayString(earlier.today, calendar: calendar)
        guard earlierToday >= freshFrom, earlierToday <= todayID,
              let oldest = Self.date(of: earlierFrom, calendar: calendar),
              let back = calendar.dateComponents([.day], from: oldest, to: today).day else { return nil }
        var joined = self
        let older = earlier.finished.filter { Self.trimmed($0.date) < freshFrom }
        joined.finished = finished + older.filter { row in !finished.contains { $0.isSameRecord(as: row) } }
        joined.readFrom = earlierFrom
        joined.unsure = unsure.union(earlier.unsure.filter { $0 < freshFrom })
        joined.mayRepeat = mayRepeat.union(earlier.mayRepeat.filter { $0 < freshFrom })
        // The next range ends the day before `earlier`'s oldest.
        joined.rangeEnd = back + 1
        joined.emptyRanges = earlier.emptyRanges
        joined.reachedEnd = earlier.reachedEnd || joined.rangeEnd >= Self.maxDaysBack
        joined.prefilled = []
        joined.prefillFrom = nil
        return joined
    }

    /// Shows home's last read (`HomeSnapshot.activity`) until this read has its days: its
    /// records on the days it holds in full (`CardActivity.holdsAll`), each day's until this read
    /// has a record of that day or an older one, or has read it, so no record shows twice. Only a
    /// read of today, before this read has any page. Those days are never complete: the list
    /// shows no day total for them, and the stats never use them, as `hasRead(through:)` waits for
    /// this read's own ranges. Nor do they count as read when the first page fails
    /// (`CardRecordsLoader`: the failed state).
    public mutating func prefill(_ activity: CardActivity) {
        let todayID = SchoolCalendar.dayString(today, calendar: calendar)
        guard readFrom == nil, finished.isEmpty, current.isEmpty, Self.trimmed(activity.end) == todayID else { return }
        let begin = Self.trimmed(activity.begin)
        let from: String
        if activity.complete {
            from = begin
        } else {
            // A page cut short holds every day after its oldest one.
            guard let oldest = activity.records.map({ Self.trimmed($0.date) }).filter({ Self.date(of: $0, calendar: calendar) != nil }).min(),
                  let date = Self.date(of: oldest, calendar: calendar),
                  let next = calendar.date(byAdding: .day, value: 1, to: date) else { return }
            from = max(begin, SchoolCalendar.dayString(next, calendar: calendar))
        }
        guard from <= todayID else { return }
        prefillFrom = from
        prefilled = activity.records.filter { row in
            let day = Self.trimmed(row.date)
            return day >= from && day <= todayID
        }
    }

    /// Whether home's records of a day (`yyyyMMdd`) show: a day home's read holds in full, older
    /// than every record this read has (so none shows twice) and not read here yet.
    var prefillShows: (String) -> Bool {
        guard let prefillFrom else { return { _ in false } }
        let todayID = SchoolCalendar.dayString(today, calendar: calendar)
        let readOldest = (finished + current).map { Self.trimmed($0.date) }.filter { Self.date(of: $0, calendar: calendar) != nil }.min()
        return { day in
            day >= prefillFrom && day <= todayID && (readOldest.map { day < $0 } ?? true) && !self.isRead(day: day)
        }
    }

    /// Reads pages until the first range is read to its end (`holdsFirstRange`), or the end.
    public static func loadFirstRange(_ history: CardHistory,
                                      fetch: (CardHistoryQuery) async throws -> CardRecordPage) async -> Load {
        var h = history
        while !h.holdsFirstRange, let query = h.nextQuery {
            do {
                h.receive(try await fetch(query), for: query)
            } catch let e as ServiceError {
                return Load(history: h, failure: e)
            } catch {
                return Load(history: h, failure: .offline)
            }
        }
        return Load(history: h, failure: nil)
    }

    /// The start of `day` (`yyyyMMdd`) in `calendar`; nil when it is not a real day.
    static func date(of day: String, calendar: Calendar) -> Date? {
        guard day.count == 8, day.allSatisfy({ $0.isASCII && $0.isNumber }),
              let y = Int(day.prefix(4)), let m = Int(day.dropFirst(4).prefix(2)), let d = Int(day.suffix(2)),
              let date = calendar.date(from: DateComponents(year: y, month: m, day: d)),
              SchoolCalendar.dayString(date, calendar: calendar) == day else { return nil }
        return date
    }
}
