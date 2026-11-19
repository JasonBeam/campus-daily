import Foundation

/// 故障排查 › 导出热水诊断: a short text file for the share sheet with the app version, the time,
/// whether a controller is bound and where the saved hot-water record stands (`DebugShowerState`:
/// phase and flags only, no ids, frames or times). Alone in a folder of its own under the
/// temporary directory; each export removes the one before, the app removes it when the sheet closes.
public enum ShowerDiagnosticReport {
    public static let title = "导出热水诊断"
    public static let footer = "仅检查已保存会话。诊断包含版本、时间和热水记录的状态，不含账号、密钥或设备编号。"
    public static let failed = "诊断文件暂未生成"
    public static let folderName = "ShowerDiagnosticExport"

    public static func directory(in temporary: URL) -> URL {
        temporary.appendingPathComponent(folderName, isDirectory: true)
    }

    /// 「校日常热水诊断 2026-11-10 2105.txt」: the local date and minute, no colon.
    public static func fileName(at date: Date, timeZone: TimeZone) -> String {
        "校日常热水诊断 \(stamp(date, timeZone: timeZone, format: "yyyy-MM-dd HHmm")).txt"
    }

    public static func text(version: String?, build: String?, now: Date, timeZone: TimeZone,
                            bound: Bool, state: ShowerState?) -> String {
        var record = "无"
        if let state {
            var f = DebugFields()
            f["phase"] = state.phase.rawValue
            f.state(DebugShowerState(state))
            record = f.text
        }
        return [
            "校日常热水诊断",
            "版本 \(version ?? "—") (\(build ?? "—"))",
            "时间 \(stamp(now, timeZone: timeZone, format: "yyyy-MM-dd HH:mm"))",
            "水控 " + (bound ? "已绑定" : "未绑定"),
            "记录 " + record,
        ].map { $0 + "\n" }.joined()
    }

    /// The file, or nil when it can't be written (nothing is left behind then).
    public static func write(_ text: String, into directory: URL, now: Date = Date(),
                             timeZone: TimeZone = .current) -> URL? {
        remove(in: directory)
        let url = directory.appendingPathComponent(fileName(at: now, timeZone: timeZone))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            remove(in: directory)
            return nil
        }
    }

    public static func remove(in directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func stamp(_ date: Date, timeZone: TimeZone, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = format
        return f.string(from: date)
    }
}
