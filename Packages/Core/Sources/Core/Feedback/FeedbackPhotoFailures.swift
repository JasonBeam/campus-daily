/// Settings › 反馈问题: how many picked photos could not be added (a download or decode that
/// failed), so the form says so instead of sending without them.
public struct FeedbackPhotoFailures: Equatable, Sendable {
    public private(set) var count = 0

    public init() {}

    /// After the photos of one pick have loaded. A pick with failures replaces the count; a pick
    /// that added photos without failures clears it.
    public mutating func finishedLoading(added: Int, failed: Int) {
        if failed > 0 { count = failed } else if added > 0 { count = 0 }
    }

    /// After a screenshot is removed: none left clears the line.
    public mutating func removed(remaining: Int) {
        if remaining == 0 { count = 0 }
    }

    /// The line under 添加截图; nil when every photo was added.
    public var line: String? { FeedbackText.photoFailure(count) }
}
