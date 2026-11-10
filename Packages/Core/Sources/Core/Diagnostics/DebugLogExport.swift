import Foundation

/// 高级 › 导出调试记录: the whole TestFlight log as one UTF-8 text file, alone in a folder of its
/// own under the temporary directory, for the share sheet. Each export first removes the one
/// before; the app removes it again when the share sheet closes.
public enum DebugLogExport {
    public static let folderName = "DebugLogExport"

    public static func directory(in temporary: URL) -> URL {
        temporary.appendingPathComponent(folderName, isDirectory: true)
    }

    /// 「校日常调试记录 2026-11-06 0841.txt」: the local date and minute, no colon.
    public static func fileName(at date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HHmm"
        return "校日常调试记录 \(f.string(from: date)).txt"
    }

    /// Every line, oldest first, each ending in a newline.
    public static func text(_ lines: [String]) -> String {
        lines.map { $0 + "\n" }.joined()
    }

    /// The file, or nil when the log keeps nothing (outside TestFlight), is empty or can't be
    /// written. Waits for every line queued before (`flush`).
    public static func write(_ log: any DebugLogSink, into directory: URL, now: Date = Date(),
                             timeZone: TimeZone = .current) -> URL? {
        remove(in: directory)
        guard log.isEnabled else { return nil }
        log.flush()
        let lines = log.lines()
        guard !lines.isEmpty else { return nil }
        let url = directory.appendingPathComponent(fileName(at: now, timeZone: timeZone))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text(lines).utf8).write(to: url, options: .atomic)
            return url
        } catch {
            remove(in: directory)
            return nil
        }
    }

    /// Deletes the folder and the export in it, if any.
    public static func remove(in directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
