import Foundation

/// Settings › 反馈问题: what the feedback service takes. Text may be empty only with a screenshot.
public enum FeedbackDraft {
    public static let maximumCharacters = 4000
    public static let maximumImages = 4

    public enum Issue: Equatable, Sendable { case empty, tooLong, tooManyImages }

    /// Why this draft can't be sent; nil when it can. Length is counted in UTF-16 units, as the
    /// service counts it.
    public static func issue(message: String, imageCount: Int) -> Issue? {
        if message.utf16.count > maximumCharacters { return .tooLong }
        if imageCount > maximumImages { return .tooManyImages }
        if imageCount == 0 && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        return nil
    }

    /// Whether 发送 is on: a draft the service takes, and no picked photo still loading (one
    /// downloading from iCloud would otherwise go out missing while the form says 发出去了).
    public static func canSend(message: String, imageCount: Int, loadingImages: Bool) -> Bool {
        !loadingImages && issue(message: message, imageCount: imageCount) == nil
    }
}
