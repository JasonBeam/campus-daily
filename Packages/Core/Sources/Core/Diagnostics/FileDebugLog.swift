import Foundation
import CryptoKit

/// The TestFlight debug log: `Application Support/DebugLog/events.log`, one JSON object per line
/// (`t`: seconds since 1970, `e`: the event's text), and `salt` beside it (32 random bytes for
/// the tags). The folder is kept out of backups before anything is written and the files are
/// readable after the first unlock. At most `maxLines` lines and `maxBytes` bytes: the oldest go
/// first. Lines older than `maxAge` go at launch (`pruneExpired`). Writes run on a serial queue
/// of their own: `record` only queues the line and never waits on the disk; `flush` waits for
/// what was queued (the feedback send, its preview, tests). `lines`, `clear` and `tag` run after
/// every line queued before them. A write that fails is dropped and never reaches the caller.
public final class FileDebugLog: DebugLogSink, @unchecked Sendable {
    // @unchecked: every field below `queue` is touched only on `queue`.
    public static let folderName = "DebugLog"
    public static let maxLines = 1000
    public static let maxBytes = 256 * 1024
    public static let maxAge: TimeInterval = 7 * 24 * 3600

    public static func directory(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    public let directory: URL
    public var eventsFile: URL { directory.appendingPathComponent("events.log") }
    public var saltFile: URL { directory.appendingPathComponent("salt") }

    private let now: @Sendable () -> Date
    private let formatter: DateFormatter
    private let maxLines: Int
    private let maxBytes: Int
    private let maxAge: TimeInterval
    private let queue: DispatchQueue

    private struct Entry: Codable { var t: Double; var e: String }
    private var entries: [Entry]?
    /// Bytes of `entries` as written (each line plus its newline).
    private var bytes = 0
    private var salt: SymmetricKey?
    private var dropped = 0

    public init(directory: URL, now: @escaping @Sendable () -> Date = Date.init, timeZone: TimeZone = .current,
                maxLines: Int = FileDebugLog.maxLines, maxBytes: Int = FileDebugLog.maxBytes, maxAge: TimeInterval = FileDebugLog.maxAge,
                queue: DispatchQueue = DispatchQueue(label: "org.zaxh.xiaorichang.debuglog")) {
        self.directory = directory; self.now = now; self.queue = queue
        self.maxLines = maxLines; self.maxBytes = maxBytes; self.maxAge = maxAge
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "MM-dd HH:mm:ss"
        formatter = f
    }

    public var isEnabled: Bool { true }

    public func record(_ event: DebugEvent) {
        let at = now()
        queue.async { [self] in
            let fields = event.fields { self.tagOnQueue($0) }
            var text = fields.isEmpty ? event.name : "\(event.name) \(fields)"
            if !DebugLogScreen.isSafe(text) {
                text = DebugLogScreen.dropped
                dropped += 1
            }
            append(Entry(t: at.timeIntervalSince1970, e: text))
        }
    }

    public func lines() -> [String] {
        queue.sync {
            load().map { "\(formatter.string(from: Date(timeIntervalSince1970: $0.t))) \($0.e)" }
        }
    }

    public func clear() {
        queue.sync {
            let fm = FileManager.default
            try? fm.removeItem(at: eventsFile)
            try? fm.removeItem(at: saltFile)
            entries = []
            bytes = 0
            salt = nil
        }
    }

    /// Waits until every line recorded before it is written.
    public func flush() { queue.sync {} }

    /// Drops the lines older than `maxAge` (at launch).
    public func pruneExpired() {
        queue.sync {
            let cutoff = now().timeIntervalSince1970 - maxAge
            let all = load()
            let kept = all.filter { $0.t >= cutoff }
            guard kept.count != all.count else { return }
            entries = kept
            rewrite()
        }
    }

    /// Lines the last check replaced with `DebugLogScreen.dropped` since launch.
    public var droppedCount: Int { queue.sync { dropped } }

    /// `kind:` plus the first 6 hex of HMAC-SHA256(salt, value).
    public func tag(_ t: DebugTag) -> String { queue.sync { tagOnQueue(t) } }

    // MARK: On the queue

    private func tagOnQueue(_ t: DebugTag) -> String {
        let key = saltKey()
        let mac = HMAC<SHA256>.authenticationCode(for: Data(t.value.utf8), using: key)
        let hex = mac.prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(t.kind.rawValue):\(hex)"
    }

    private func saltKey() -> SymmetricKey {
        if let salt { return salt }
        if let data = try? Data(contentsOf: saltFile), data.count == 32 {
            salt = SymmetricKey(data: data)
            return salt!
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        var rng = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = rng.next() }
        let data = Data(bytes)
        if prepareDirectory() { try? write(data, to: saltFile) }
        salt = SymmetricKey(data: data)
        return salt!
    }

    private func load() -> [Entry] {
        if let entries { return entries }
        var loaded: [Entry] = []
        var size = 0
        if let data = try? Data(contentsOf: eventsFile) {
            let decoder = JSONDecoder()
            for line in data.split(separator: UInt8(ascii: "\n")) {
                // A line that no longer decodes or passes the check is left out.
                guard let entry = try? decoder.decode(Entry.self, from: Data(line)), DebugLogScreen.isSafe(entry.e)
                        || entry.e == DebugLogScreen.dropped else { continue }
                loaded.append(entry)
                size += line.count + 1
            }
        }
        entries = loaded
        bytes = size
        return loaded
    }

    private func encoded(_ entry: Entry) -> Data? {
        guard var data = try? JSONEncoder().encode(entry) else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private func append(_ entry: Entry) {
        var all = load()
        guard let line = encoded(entry), line.count <= maxBytes else { return }
        all.append(entry)
        bytes += line.count
        entries = all
        if all.count > maxLines || bytes > maxBytes {
            var cut = 0
            var size = bytes
            while all.count - cut > maxLines || size > maxBytes, cut < all.count {
                size -= (encoded(all[cut])?.count ?? 0)
                cut += 1
            }
            entries = Array(all.dropFirst(cut))
            rewrite()
            return
        }
        guard prepareDirectory() else { return }
        if let handle = try? FileHandle(forWritingTo: eventsFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? write(line, to: eventsFile)
        }
    }

    private func rewrite() {
        let all = entries ?? []
        var data = Data()
        for entry in all { if let line = encoded(entry) { data.append(line) } }
        bytes = data.count
        guard prepareDirectory() else { return }
        if all.isEmpty { try? FileManager.default.removeItem(at: eventsFile); return }
        try? write(data, to: eventsFile)
    }

    /// Creates the folder (kept out of backups before anything is in it). False: it can't be.
    private func prepareDirectory() -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: directory.path, isDirectory: &isDirectory) { return isDirectory.boolValue }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: Self.protection)
            var url = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private static var protection: [FileAttributeKey: Any]? {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        return nil
        #endif
    }
}

/// The last check before a line is written or sent. Not the defence (events take no text):
/// a line with a run of 8 digits, 16 hex characters, a credential word or anything but ASCII
/// is replaced whole.
public enum DebugLogScreen {
    public static let dropped = "<dropped>"
    static let words = ["bearer", "token=", "acc_token", "cookie", "password", "passwd", "secret", "sid=", "ticket="]

    public static func isSafe(_ line: String) -> Bool {
        guard line.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        if line.range(of: "[0-9]{8,}", options: .regularExpression) != nil { return false }
        if line.range(of: "[0-9A-Fa-f]{16,}", options: .regularExpression) != nil { return false }
        let lower = line.lowercased()
        return !words.contains { lower.contains($0) }
    }
}

/// The log as it rides in a feedback message: AirFeedback takes only `message` (at most 4000
/// UTF-16 units) and screenshots, so the newest lines (at most `maxLines`) follow the typed text
/// under a header, the oldest left out first until both fit. A line that fails the last check
/// is left out.
public enum DebugLogReport {
    public static let maxLines = 100

    static func header(_ count: Int) -> String { "— 调试记录（测试版，最近 \(count) 条）—" }

    public static func message(_ text: String, lines: [String], limit: Int = FeedbackDraft.maximumCharacters) -> String {
        var kept = Array(lines.filter(DebugLogScreen.isSafe).suffix(maxLines))
        let lead = text.isEmpty ? "" : text + "\n\n"
        func compose(_ k: [String]) -> String { lead + header(k.count) + "\n" + k.joined(separator: "\n") }
        while !kept.isEmpty, compose(kept).utf16.count > limit { kept.removeFirst() }
        return kept.isEmpty ? text : compose(kept)
    }
}

/// Picks the log once at launch. A TestFlight install keeps it (week-old lines dropped); any
/// other install deletes a folder left by a TestFlight build and keeps nothing.
public enum DebugLogLaunch {
    public static func sink(isTestFlight: Bool, applicationSupport: URL?, now: @escaping @Sendable () -> Date = Date.init) -> any DebugLogSink {
        guard let applicationSupport else { return NoDebugLog() }
        let folder = FileDebugLog.directory(in: applicationSupport)
        guard isTestFlight else {
            if FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) }
            return NoDebugLog()
        }
        let log = FileDebugLog(directory: folder, now: now)
        log.pruneExpired()
        return log
    }
}
