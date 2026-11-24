//
//  WidgetDebugLog.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import Foundation
import CryptoKit

/// The widget's part of the TestFlight debug log: `DebugLog/widget.log` in the App Group
/// container, the same JSON lines as `FileDebugLog`, beside `salt`, the app's salt, which the
/// app copies there only once StoreKit said the install is TestFlight (`FileDebugLog.shared`).
/// No salt there (App Store, Xcode, the sample, before the app knew, right after the app
/// deleted the folder): the widget writes nothing. The app reads these lines into its own
/// (`FileDebugLog.lines`, so the export has them) and empties them with its own.
///
/// Only the widget writes the file, on a queue of its own (never the caller's thread): one
/// line at a time inside an exclusive `flock` on `widget.lock`, taken without waiting
/// (`LOCK_NB`) and tried again for at most `lockWait` (two widget timelines at once); not free
/// by then, the line is dropped. Inside the lock the salt is read again: gone or not the one
/// the line was tagged with (the app emptied the log, or took the salt back meanwhile), the
/// line is dropped, so a write in flight never brings back the lines the app removed. The
/// widget never makes the folder or the file without the salt. A line is appended in one
/// write; a cut (lines older than `maxAge`, past `maxLines` or `maxBytes`) replaces the file
/// atomically, so the app reads it without the lock and never sees half a file. The app
/// removes the lines and the salt inside the same lock (`remove`).
public final class WidgetDebugLog: DebugLogSink, @unchecked Sendable {
    // @unchecked: immutable apart from what only `queue` touches (the files).
    public static let maxLines = 200
    public static let maxBytes = 64 * 1024
    public static let maxAge: TimeInterval = FileDebugLog.maxAge
    public static let lockWait: TimeInterval = 0.2
    /// How long the app's removal waits for a widget write in flight (off the main thread).
    public static let removeLockWait: TimeInterval = 1

    static let saltName = "salt"
    static let logName = "widget.log"
    static let lockName = "widget.lock"

    /// The App Group's `DebugLog` folder; nil without a usable group.
    public static func folder(appGroup: String? = AppIdentity.usableAppGroup) -> URL? {
        appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            .map { $0.appendingPathComponent(FileDebugLog.folderName, isDirectory: true) }
    }

    /// The widget's log in the App Group, or `NoDebugLog` without one.
    public static func shared() -> any DebugLogSink { folder().map { WidgetDebugLog(folder: $0) } ?? NoDebugLog() }

    public let folder: URL
    private let now: @Sendable () -> Date
    private let maxLines: Int, maxBytes: Int, maxAge: TimeInterval, lockWait: TimeInterval
    private let queue: DispatchQueue
    /// Tests: run after the salt was read, before the lock is taken / once it is held.
    private let beforeLock: (@Sendable () -> Void)?, insideLock: (@Sendable () -> Void)?

    public convenience init(folder: URL, now: @escaping @Sendable () -> Date = Date.init, maxLines: Int = WidgetDebugLog.maxLines,
                maxBytes: Int = WidgetDebugLog.maxBytes, maxAge: TimeInterval = WidgetDebugLog.maxAge,
                lockWait: TimeInterval = WidgetDebugLog.lockWait,
                queue: DispatchQueue = DispatchQueue(label: "org.zaxh.xiaorichang.debuglog.widget")) {
        self.init(folder: folder, now: now, maxLines: maxLines, maxBytes: maxBytes, maxAge: maxAge, lockWait: lockWait,
                  queue: queue, beforeLock: nil, insideLock: nil)
    }

    init(folder: URL, now: @escaping @Sendable () -> Date = Date.init, maxLines: Int = WidgetDebugLog.maxLines,
         maxBytes: Int = WidgetDebugLog.maxBytes, maxAge: TimeInterval = WidgetDebugLog.maxAge,
         lockWait: TimeInterval = WidgetDebugLog.lockWait, queue: DispatchQueue,
         beforeLock: (@Sendable () -> Void)?, insideLock: (@Sendable () -> Void)?) {
        self.folder = folder; self.now = now; self.maxLines = maxLines; self.maxBytes = maxBytes
        self.maxAge = maxAge; self.lockWait = lockWait; self.queue = queue
        self.beforeLock = beforeLock; self.insideLock = insideLock
    }

    /// The app shared its salt: the install is TestFlight and the log is on.
    public var isEnabled: Bool { Self.salt(in: folder) != nil }

    public func record(_ event: DebugEvent) {
        let at = now()
        queue.async { [self] in write(event, at: at) }
    }

    /// The app reads the widget's lines (`FileDebugLog.lines`), not the widget.
    public func lines() -> [String] { [] }
    /// The app empties them (`FileDebugLog.clear`).
    public func clear() {}
    public func flush() { queue.sync {} }

    // MARK: Shared with the app

    struct Entry: Codable { var t: Double; var e: String }

    /// The widget's lines no older than `cutoff`, as written (a line that doesn't decode or
    /// pass the screen is left out).
    static func entries(in folder: URL, after cutoff: Double = -.infinity) -> [Entry] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(logName)) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { line in
            guard let entry = try? decoder.decode(Entry.self, from: Data(line)), entry.t >= cutoff,
                  DebugLogScreen.isSafe(entry.e) || entry.e == DebugLogScreen.dropped else { return nil }
            return entry
        }
    }

    /// Writes the app's salt for the widget (unless it is there already). False: not written.
    static func share(salt: Data, in folder: URL) -> Bool {
        if self.salt(in: folder) == salt { return true }
        guard prepare(folder) else { return false }
        return (try? write(salt, to: folder.appendingPathComponent(saltName))) != nil
    }

    /// What the app removes (`remove`).
    enum Removal {
        /// Only the salt: the widget stops writing, its lines stay (the install not known).
        case salt
        /// The lines and the salt (a sign-out, 清空调试记录).
        case linesAndSalt
        /// The whole folder (an App Store install).
        case folder
    }

    /// Removes inside `widget.lock`, waited for at most `wait` (blocking: never on the main
    /// thread), so a widget write in flight finishes first and the next one finds the salt
    /// gone. Still held after `wait` (a widget suspended inside its write): removed all the
    /// same; that write's own salt check inside the lock still drops its line.
    static func remove(_ removal: Removal, in folder: URL, wait: TimeInterval = removeLockWait) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return }
        let remove = {
            switch removal {
            case .salt:
                try? fm.removeItem(at: folder.appendingPathComponent(saltName))
            case .linesAndSalt:
                try? fm.removeItem(at: folder.appendingPathComponent(saltName))
                try? fm.removeItem(at: folder.appendingPathComponent(logName))
            case .folder:
                try? fm.removeItem(at: folder)
            }
        }
        if !withLock(in: folder, wait: wait, remove) { remove() }
    }

    static func salt(in folder: URL) -> Data? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(saltName)), data.count == 32 else { return nil }
        return data
    }

    // MARK: On the queue

    private func write(_ event: DebugEvent, at: Date) {
        guard let salt = Self.salt(in: folder) else { return }
        let key = SymmetricKey(data: salt)
        let fields = event.fields { FileDebugLog.tag($0, key: key) }
        var text = fields.isEmpty ? event.name : "\(event.name) \(fields)"
        if !DebugLogScreen.isSafe(text) { text = DebugLogScreen.dropped }
        guard var line = try? JSONEncoder().encode(Entry(t: at.timeIntervalSince1970, e: text)) else { return }
        line.append(UInt8(ascii: "\n"))
        guard line.count <= maxBytes else { return }
        beforeLock?()
        _ = Self.withLock(in: folder, wait: lockWait) { [self] in
            insideLock?()
            // Still the salt this line was tagged with: not taken back or replaced meanwhile.
            guard Self.salt(in: folder) == salt else { return }
            let url = folder.appendingPathComponent(Self.logName)
            let cutoff = now().timeIntervalSince1970 - maxAge
            let kept = Self.entries(in: folder, after: cutoff)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let all = Self.entries(in: folder).count
            if kept.count == all, all < maxLines, size + line.count <= maxBytes,
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
                return
            }
            // A cut, or the first line: the whole file is written again, atomically.
            var lines = kept.compactMap { try? JSONEncoder().encode($0) }.map { $0 + Data("\n".utf8) } + [line]
            var total = lines.reduce(0) { $0 + $1.count }
            while lines.count > maxLines || total > maxBytes, !lines.isEmpty { total -= lines.removeFirst().count }
            try? Self.write(lines.reduce(Data(), +), to: url)
        }
    }

    /// Runs `body` inside the exclusive lock on `widget.lock` in an existing `folder` (never
    /// made here). False: not run (no folder, or not free within `wait`). Blocks the calling
    /// thread for at most `wait`: the widget's queue, the app's log queue or its removals.
    @discardableResult
    static func withLock(in folder: URL, wait: TimeInterval, _ body: () -> Void) -> Bool {
        let fd = open(folder.appendingPathComponent(lockName).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let deadline = Date().addingTimeInterval(wait)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, Date() < deadline else { return false }
            usleep(10_000)
        }
        defer { flock(fd, LOCK_UN) }
        body()
        return true
    }

    /// The folder exists (kept out of backups). False: it can't be made.
    private static func prepare(_ folder: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: folder.path, isDirectory: &isDirectory) { return isDirectory.boolValue }
        do {
            #if os(iOS)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            #else
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            #endif
            var url = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
