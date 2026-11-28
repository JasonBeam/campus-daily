//
//  CardHistory+Cache.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/27.
//

import Foundation
import CryptoKit

/// App-private Keychain anchor (`StoreKey.cardHistorySession`, `whenUnlockedThisDeviceOnly`)
/// binding a session's private disk cache directory (`CardHistory/<sessionID>/cache.v1.json`)
/// to both the cross-process `SessionEpoch.id` and a 32-byte random salt.
/// Contains no plaintext student ID, card number, `custid`, or `voucher`.
public struct CardHistorySessionAnchor: Codable, Equatable, Sendable {
    public var epochID: String
    public var sessionID: String
    public var salt: Data

    public init(epochID: String, sessionID: String, salt: Data) {
        self.epochID = epochID
        self.sessionID = sessionID
        self.salt = salt
    }

    /// Canonical uppercase hyphenated UUID string (`UUID(uuidString:)` round-trip).
    /// Prevents any malformed or path-traversal `sessionID` from reaching filesystem deletion.
    public static func isCanonicalSessionID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return value == uuid.uuidString
    }

    public var isValid: Bool {
        !epochID.isEmpty && Self.isCanonicalSessionID(sessionID) && salt.count == 32
    }
}

/// Whitelisted on-disk JSON envelope for `<Application Support>/CardHistory/<sessionID>/cache.v1.json`.
/// Never stores `voucher`, plaintext account/card IDs, tokens, passwords, residence, or half-read pages.
public struct CardHistoryDiskEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var ownerTag: String
    /// When this cache file was written to disk.
    public var savedAt: Date
    /// When the newest 14-day range was last successfully read from the school (used for the
    /// offline "as of HH:mm" hint; nil in legacy v1 envelopes falls back to `savedAt`).
    public var latestReadAt: Date?
    public var today: String
    public var readFrom: String
    public var emptyRanges: Int
    public var reachedEnd: Bool
    public var unsure: [String]
    public var mayRepeat: [String]
    public var records: [CardRecord]

    public init(schemaVersion: Int = currentSchemaVersion,
                ownerTag: String,
                savedAt: Date,
                latestReadAt: Date? = nil,
                today: String,
                readFrom: String,
                emptyRanges: Int,
                reachedEnd: Bool,
                unsure: [String],
                mayRepeat: [String],
                records: [CardRecord]) {
        self.schemaVersion = schemaVersion
        self.ownerTag = ownerTag
        self.savedAt = savedAt
        self.latestReadAt = latestReadAt
        self.today = today
        self.readFrom = readFrom
        self.emptyRanges = emptyRanges
        self.reachedEnd = reachedEnd
        self.unsure = unsure
        self.mayRepeat = mayRepeat
        self.records = records
    }
}

/// Validated cached history loaded from memory or disk, along with its file write time (`savedAt`),
/// newest-range read time (`latestReadAt`), and optional session provenance.
public struct CachedCardHistory: Equatable, Sendable {
    public var history: CardHistory
    public var savedAt: Date?
    public var latestReadAt: Date?
    public var epochID: String?
    public var sessionID: String?

    public init(history: CardHistory,
                savedAt: Date?,
                latestReadAt: Date? = nil,
                epochID: String? = nil,
                sessionID: String? = nil) {
        self.history = history
        self.savedAt = savedAt
        self.latestReadAt = latestReadAt ?? savedAt
        self.epochID = epochID
        self.sessionID = sessionID
    }
}

public extension CardHistory {
    /// Read/write retention window: keep at most 210 days of complete ranges ending on `today`.
    static let maxCacheDays = 210
    /// Encoded JSON upper bound: 1 MiB. Older days are trimmed forward until within budget.
    static let maxCacheBytes = 1_048_576
    /// Maximum age on open before a cached history is discarded and rebuilt from the school.
    static let maxCacheAge: TimeInterval = 30 * 24 * 3600

    /// Computes HMAC-SHA256(salt, confirmedIdentity) as lowercase hex.
    static func ownerTag(identity: String, salt: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(identity.utf8), using: SymmetricKey(data: salt))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Serializes finished ranges of this history into a whitelisted, size-bounded JSON envelope.
    /// Returns `nil` when the first range is not yet complete (`!holdsFirstRange`) or when even
    /// a single day exceeds `maxBytes`. Never includes in-flight `current` half-pages or `prefilled`.
    func cacheEnvelope(ownerTag: String,
                       savedAt: Date,
                       latestReadAt: Date? = nil,
                       maxDays: Int = CardHistory.maxCacheDays,
                       maxBytes: Int = CardHistory.maxCacheBytes) -> (envelope: CardHistoryDiskEnvelope, data: Data)? {
        guard let initialReadFrom = readFrom,
              let oldestDate = Self.date(of: initialReadFrom, calendar: calendar) else { return nil }
        let todayID = SchoolCalendar.dayString(today, calendar: calendar)
        guard initialReadFrom <= todayID else { return nil }
        let effectiveLatestReadAt = latestReadAt ?? savedAt

        let cutoffDate = calendar.date(byAdding: .day, value: -(max(maxDays, 1) - 1), to: today) ?? today
        let cutoffID = SchoolCalendar.dayString(cutoffDate, calendar: calendar)

        let effectiveReadFrom = max(initialReadFrom, cutoffID)
        let effectiveReachedEnd = reachedEnd && effectiveReadFrom == initialReadFrom

        let mergedFinished = WeChatPairs.merged(finished) { _ in true }.map { row in
            var copy = row
            copy.voucher = nil
            return copy
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate

        func makeEnvelope(from floorDay: String, reachedEnd: Bool) -> (CardHistoryDiskEnvelope, Data)? {
            let filteredRecords = mergedFinished.filter { row in
                let day = Self.trimmed(row.date)
                return day >= floorDay && day <= todayID
            }
            let filteredUnsure = unsure.filter { $0 >= floorDay && $0 <= todayID }.sorted()
            let filteredMayRepeat = mayRepeat.filter { $0 >= floorDay && $0 <= todayID }.sorted()
            let envelope = CardHistoryDiskEnvelope(
                ownerTag: ownerTag,
                savedAt: savedAt,
                latestReadAt: effectiveLatestReadAt,
                today: todayID,
                readFrom: floorDay,
                emptyRanges: emptyRanges,
                reachedEnd: reachedEnd,
                unsure: filteredUnsure,
                mayRepeat: filteredMayRepeat,
                records: filteredRecords
            )
            guard let data = try? encoder.encode(envelope) else { return nil }
            return (envelope, data)
        }

        if let first = makeEnvelope(from: effectiveReadFrom, reachedEnd: effectiveReachedEnd),
           first.1.count <= maxBytes {
            return first
        }

        // Over byte budget: binary-search the earliest floor day within [effectiveReadFrom...today]
        // whose encoded envelope fits in `maxBytes`, always setting `reachedEnd = false`.
        let startDate = max(oldestDate, cutoffDate)
        guard let totalDays = calendar.dateComponents([.day], from: startDate, to: today).day,
              totalDays >= 0 else { return nil }
        var low = 1
        var high = totalDays
        var best: (CardHistoryDiskEnvelope, Data)?

        while low <= high {
            let mid = (low + high) / 2
            guard let candidateDate = calendar.date(byAdding: .day, value: mid, to: startDate) else { break }
            let candidateID = SchoolCalendar.dayString(candidateDate, calendar: calendar)
            if let encoded = makeEnvelope(from: candidateID, reachedEnd: false), encoded.1.count <= maxBytes {
                best = encoded
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return best
    }

    /// Reconstructs a `CardHistory` from a validated disk envelope, enforcing schema version,
    /// 30-day open age limit (against both `latestReadAt` and `savedAt`), and the 210-day
    /// retention window anchored to the open day (`now`, never older than `envelope.today`).
    static func fromCacheEnvelope(_ envelope: CardHistoryDiskEnvelope,
                                  now: Date,
                                  calendar: Calendar = SchoolCalendar.shanghai,
                                  maxDays: Int = CardHistory.maxCacheDays,
                                  maxAge: TimeInterval = CardHistory.maxCacheAge) -> CardHistory? {
        guard envelope.schemaVersion == CardHistoryDiskEnvelope.currentSchemaVersion else { return nil }
        let effectiveLatest = envelope.latestReadAt ?? envelope.savedAt
        guard now.timeIntervalSince(envelope.savedAt) <= maxAge,
              now.timeIntervalSince(effectiveLatest) <= maxAge else { return nil }
        guard let todayDate = Self.date(of: envelope.today, calendar: calendar),
              let rawReadFromDate = Self.date(of: envelope.readFrom, calendar: calendar),
              envelope.readFrom <= envelope.today else { return nil }

        let openToday = max(calendar.startOfDay(for: now), todayDate)
        let cutoffDate = calendar.date(byAdding: .day, value: -(max(maxDays, 1) - 1), to: openToday) ?? openToday
        let cutoffID = SchoolCalendar.dayString(cutoffDate, calendar: calendar)
        guard cutoffID <= envelope.today else { return nil }

        let effectiveReadFrom = max(envelope.readFrom, cutoffID)
        let effectiveReadFromDate = max(rawReadFromDate, cutoffDate)
        let prunedOlder = effectiveReadFrom != envelope.readFrom
        guard let back = calendar.dateComponents([.day], from: effectiveReadFromDate, to: todayDate).day,
              back >= 0 else { return nil }

        var history = CardHistory(now: todayDate, calendar: calendar)
        history.finished = envelope.records.filter { row in
            let day = Self.trimmed(row.date)
            return day >= effectiveReadFrom && day <= envelope.today
        }
        history.current = []
        history.readFrom = effectiveReadFrom
        history.unsure = Set(envelope.unsure.filter { $0 >= effectiveReadFrom && $0 <= envelope.today })
        history.mayRepeat = Set(envelope.mayRepeat.filter { $0 >= effectiveReadFrom && $0 <= envelope.today })
        history.rangeEnd = back + 1
        history.emptyRanges = max(0, envelope.emptyRanges)
        history.reachedEnd = (!prunedOlder && envelope.reachedEnd) || history.rangeEnd >= Self.maxDaysBack
        history.prefilled = []
        history.prefillFrom = nil
        return history
    }

    /// Trims an in-memory `CardHistory` to the 210-day retention window anchored to `now` (open
    /// day), matching `fromCacheEnvelope`. Returns `nil` when the entire cached history falls
    /// outside the window or has no finished range.
    func trimmedToCacheWindow(now: Date, maxDays: Int = CardHistory.maxCacheDays) -> CardHistory? {
        guard let currentReadFrom = readFrom,
              let rawReadFromDate = Self.date(of: currentReadFrom, calendar: calendar) else { return nil }
        let todayID = SchoolCalendar.dayString(today, calendar: calendar)
        guard currentReadFrom <= todayID else { return nil }

        let openToday = max(calendar.startOfDay(for: now), today)
        let cutoffDate = calendar.date(byAdding: .day, value: -(max(maxDays, 1) - 1), to: openToday) ?? openToday
        let cutoffID = SchoolCalendar.dayString(cutoffDate, calendar: calendar)
        guard cutoffID <= todayID else { return nil }

        if cutoffID <= currentReadFrom { return self }

        let effectiveReadFrom = max(currentReadFrom, cutoffID)
        let effectiveReadFromDate = max(rawReadFromDate, cutoffDate)
        guard let back = calendar.dateComponents([.day], from: effectiveReadFromDate, to: today).day,
              back >= 0 else { return nil }

        var copy = self
        copy.finished = finished.filter { row in
            let day = Self.trimmed(row.date)
            return day >= effectiveReadFrom && day <= todayID
        }
        copy.current = []
        copy.readFrom = effectiveReadFrom
        copy.unsure = Set(unsure.filter { $0 >= effectiveReadFrom && $0 <= todayID })
        copy.mayRepeat = Set(mayRepeat.filter { $0 >= effectiveReadFrom && $0 <= todayID })
        copy.rangeEnd = back + 1
        copy.reachedEnd = copy.rangeEnd >= Self.maxDaysBack
        copy.prefilled = []
        copy.prefillFrom = nil
        return copy
    }
}
