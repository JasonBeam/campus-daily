import Core

/// 高级 › 清空调试记录 (TestFlight only): what the row says and whether it can be tapped. Read
/// after every line queued before it is written (`flush`), so a line just recorded counts.
struct DebugLogClearRow: Equatable {
    /// The log has no line to clear.
    let isEmpty: Bool
    /// Cleared from this row since the page opened.
    let cleared: Bool

    init(log: any DebugLogSink, cleared: Bool) {
        if log.isEnabled {
            log.flush()
            isEmpty = log.lines().isEmpty
        } else {
            isEmpty = true
        }
        self.cleared = cleared
    }

    static let title = "清空调试记录"
    static let footer = "调试记录只存在这台手机上，最多留 7 天，退出登录也会清空。"
    static let clearedLine = "已清空"
    static let confirmTitle = "清空调试记录？"
    static let confirmButton = "清空"
    static let cancelButton = "取消"
    static let emptyLabel = "没有调试记录"

    /// Nothing to clear: off (and after a clear, there is nothing left).
    var disabled: Bool { isEmpty }
    /// VoiceOver says why the row is off.
    var accessibilityLabel: String { isEmpty ? Self.emptyLabel : Self.title }
}
