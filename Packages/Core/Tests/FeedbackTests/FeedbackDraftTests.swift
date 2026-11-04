import XCTest
import Core

/// Settings › 反馈问题: what may be sent, and the line shown when the text is too long.
final class FeedbackDraftTests: XCTestCase {
    func testEmptyTextNeedsAnImage() {
        XCTAssertEqual(FeedbackDraft.issue(message: "", imageCount: 0), .empty)
        XCTAssertEqual(FeedbackDraft.issue(message: " \n\t", imageCount: 0), .empty, "whitespace only is empty")
        XCTAssertNil(FeedbackDraft.issue(message: "", imageCount: 1), "a screenshot alone may be sent")
        XCTAssertNil(FeedbackDraft.issue(message: "热水页面打不开", imageCount: 0))
    }

    func testAtMost4000Characters() {
        XCTAssertNil(FeedbackDraft.issue(message: String(repeating: "字", count: 4000), imageCount: 0))
        XCTAssertEqual(FeedbackDraft.issue(message: String(repeating: "字", count: 4001), imageCount: 0), .tooLong)
        // Counted as the server counts them (UTF-16), so an emoji takes two.
        XCTAssertEqual(FeedbackDraft.issue(message: String(repeating: "🚿", count: 2001), imageCount: 0), .tooLong)
        XCTAssertEqual(FeedbackDraft.issue(message: String(repeating: "a", count: 4001), imageCount: 1), .tooLong)
    }

    func testAtMostFourImages() {
        XCTAssertNil(FeedbackDraft.issue(message: "看图", imageCount: 4))
        XCTAssertEqual(FeedbackDraft.issue(message: "看图", imageCount: 5), .tooManyImages)
        XCTAssertEqual(FeedbackDraft.maximumImages, 4)
    }

    func testNotSendableWhilePhotosLoad() {
        // A picked photo still downloading (iCloud) would go out missing and still read 发出去了.
        XCTAssertFalse(FeedbackDraft.canSend(message: "看图", imageCount: 1, loadingImages: true))
        XCTAssertFalse(FeedbackDraft.canSend(message: "看图", imageCount: 0, loadingImages: true),
                       "the text alone waits for the photo too")
        XCTAssertTrue(FeedbackDraft.canSend(message: "看图", imageCount: 1, loadingImages: false))
        XCTAssertTrue(FeedbackDraft.canSend(message: "", imageCount: 1, loadingImages: false))
    }

    func testCanSendFollowsTheDraftRules() {
        XCTAssertFalse(FeedbackDraft.canSend(message: "", imageCount: 0, loadingImages: false))
        XCTAssertFalse(FeedbackDraft.canSend(message: String(repeating: "字", count: 4001), imageCount: 0, loadingImages: false))
        XCTAssertFalse(FeedbackDraft.canSend(message: "看图", imageCount: 5, loadingImages: false))
    }

    func testOnlyTooLongHasALine() {
        XCTAssertEqual(FeedbackText.issue(.tooLong), "最多 4000 字。")
        XCTAssertNil(FeedbackText.issue(.empty), "an empty form only disables 发送")
        XCTAssertNil(FeedbackText.issue(.tooManyImages), "the picker never takes a fifth")
        XCTAssertNil(FeedbackText.issue(nil))
    }
}
