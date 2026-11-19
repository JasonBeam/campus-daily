import XCTest
import Core

/// Settings › 反馈问题: the line under 添加截图 when a picked photo could not be added.
final class FeedbackPhotoFailuresTests: XCTestCase {
    func testNoLineAtFirst() {
        XCTAssertEqual(FeedbackPhotoFailures().count, 0)
        XCTAssertNil(FeedbackPhotoFailures().line)
    }

    func testAFailedLoadIsCounted() {
        var failures = FeedbackPhotoFailures()
        failures.finishedLoading(added: 2, failed: 1)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.line, "有 1 张截图没加上，再选一次试试。")
        failures.finishedLoading(added: 0, failed: 2)
        XCTAssertEqual(failures.count, 2, "a new pick replaces the old count")
        XCTAssertEqual(failures.line, "有 2 张截图没加上，再选一次试试。")
    }

    func testASuccessfulPickClearsTheLine() {
        var failures = FeedbackPhotoFailures()
        failures.finishedLoading(added: 0, failed: 1)
        failures.finishedLoading(added: 1, failed: 0)
        XCTAssertNil(failures.line)
    }

    func testAnEmptyPickKeepsTheLine() {
        var failures = FeedbackPhotoFailures()
        failures.finishedLoading(added: 0, failed: 1)
        failures.finishedLoading(added: 0, failed: 0)
        XCTAssertEqual(failures.count, 1)
    }

    func testRemovingEveryScreenshotClearsTheLine() {
        var failures = FeedbackPhotoFailures()
        failures.finishedLoading(added: 2, failed: 1)
        failures.removed(remaining: 1)
        XCTAssertEqual(failures.count, 1, "screenshots are still there")
        failures.removed(remaining: 0)
        XCTAssertNil(failures.line)
    }

    func testLineText() {
        XCTAssertNil(FeedbackText.photoFailure(0))
        XCTAssertEqual(FeedbackText.photoFailure(1), "有 1 张截图没加上，再选一次试试。")
        XCTAssertEqual(FeedbackText.photoFailure(2), "有 2 张截图没加上，再选一次试试。")
    }
}
