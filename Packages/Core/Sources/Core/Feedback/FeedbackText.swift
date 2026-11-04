/// The feedback form's fixed lines. The service's own words are never shown.
public enum FeedbackText {
    public static let failureText = "没发出去，检查一下网络再试一次。"
    public static let tooLongText = "最多 4000 字。"

    /// The line under the text for a draft that can't be sent; nil when there is nothing to say.
    public static func issue(_ issue: FeedbackDraft.Issue?) -> String? {
        issue == .tooLong ? tooLongText : nil
    }

    /// Every failed send reads the same.
    public static func failure(_ error: Error) -> String { failureText }
}
