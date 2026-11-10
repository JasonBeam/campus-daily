import Foundation
import Core

/// 高级 › 导出调试记录 (TestFlight only): what the row says and whether it can be tapped, read after
/// every line queued before it is written (`flush`), like `DebugLogClearRow`.
struct DebugLogExportRow: Equatable {
    /// The log has no line to export.
    let isEmpty: Bool

    init(log: any DebugLogSink) {
        if log.isEnabled {
            log.flush()
            isEmpty = log.lines().isEmpty
        } else {
            isEmpty = true
        }
    }

    static let title = "导出调试记录"
    static let emptyLabel = DebugLogClearRow.emptyLabel

    /// Nothing to export: off.
    var disabled: Bool { isEmpty }
    /// VoiceOver says why the row is off.
    var accessibilityLabel: String { isEmpty ? Self.emptyLabel : Self.title }

    /// The export's folder under `temporary` (the app's temporary directory).
    static func folder(in temporary: URL) -> URL { DebugLogExport.directory(in:temporary) }

    /// The whole log as a text file for the share sheet, replacing the last export; nil with nothing to export.
    static func file(from log: any DebugLogSink, in temporary: URL, now: Date = Date(), timeZone: TimeZone = .current) -> URL? {
        DebugLogExport.write(log, into:folder(in:temporary), now:now, timeZone:timeZone)
    }
}
