//
//  FeedbackText.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/04.
//

import Foundation

/// The feedback form's fixed lines. The service's own words are never shown.
public enum FeedbackText {
    public static let failureText = "没发出去，检查一下网络再试一次。"
    public static let tooLongText = "最多 4000 字。"
    /// `%d`: how many picked photos could not be added.
    public static let photoFailureFormat = "有 %d 张截图没加上，再选一次试试。"

    /// The line under the text for a draft that can't be sent; nil when there is nothing to say.
    public static func issue(_ issue: FeedbackDraft.Issue?) -> String? {
        issue == .tooLong ? tooLongText : nil
    }

    /// Every failed send reads the same.
    public static func failure(_ error: Error) -> String { failureText }

    /// A failed send: with screenshots it says fewer may get through; text alone reads `failureText`.
    public static func failure(withScreenshots: Bool, clear: Bool) -> String {
        guard withScreenshots else { return failureText }
        return clear ? "发送失败；网络较慢时可减少截图后重试" : "没发出去。网络慢的话，少带几张截图再试。"
    }

    /// A send still going after this long shows `slow(clear:)` under the form.
    public static let slowAfter: TimeInterval = 5

    /// Under the form while a slow send is still going. It never says it is nearly done.
    public static func slow(clear: Bool) -> String {
        clear ? "网络较慢，仍在发送；可点「取消」停止" : "网络有点慢，还在发。不想等可以点取消。"
    }

    /// The line under 添加截图 when `count` picked photos could not be added; nil for none.
    public static func photoFailure(_ count: Int) -> String? {
        count > 0 ? String(format: photoFailureFormat, count) : nil
    }
}
