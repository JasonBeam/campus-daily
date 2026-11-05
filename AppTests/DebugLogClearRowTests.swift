import XCTest
import Core
@testable import XiaoRiChang

/// 高级 › 清空调试记录: off with nothing to clear (and VoiceOver says so), on with lines,
/// 「已清空」 after a clear.
final class DebugLogClearRowTests: XCTestCase {
    func testTheRowWordsAreFinal() {
        XCTAssertEqual(DebugLogClearRow.title, "清空调试记录")
        XCTAssertEqual(DebugLogClearRow.footer, "调试记录只存在这台手机上，最多留 7 天，退出登录也会清空。")
        XCTAssertEqual(DebugLogClearRow.clearedLine, "已清空")
        XCTAssertEqual(DebugLogClearRow.confirmTitle, "清空调试记录？")
        XCTAssertEqual(DebugLogClearRow.confirmButton, "清空")
        XCTAssertEqual(DebugLogClearRow.cancelButton, "取消")
    }

    func testTheFeedbackWordsAreFinal() {
        XCTAssertEqual(FeedbackLogText.toggle, "附上调试记录")
        XCTAssertEqual(FeedbackLogText.footer, "会带上最近的操作步骤：点了什么、走到哪一步、请求成没成。不带密码、账号、学号、姓名和宿舍，机器和订单只记一串代号。")
        XCTAssertEqual(FeedbackLogText.showButton, "看看内容")
        XCTAssertEqual(FeedbackLogText.previewTitle, "将要发出的调试记录")
    }

    /// The form reads what was queued just before (record only queues the line).
    func testTheFormReadsALineJustRecorded() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apptests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = FileDebugLog(directory: dir)
        log.record(.navOpen(.feedback, from: .settings))
        XCTAssertEqual(FeedbackView.readLog(log).count, 1)
        XCTAssertEqual(FeedbackView.readLog(NoDebugLog()), [])
    }

    func testAnEmptyLogDisablesTheRowAndSaysSo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apptests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = FileDebugLog(directory: dir)
        let row = DebugLogClearRow(log: log, cleared: false)
        XCTAssertTrue(row.isEmpty)
        XCTAssertTrue(row.disabled)
        XCTAssertEqual(row.accessibilityLabel, "没有调试记录")
    }

    func testALogWithLinesCanBeCleared() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apptests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = FileDebugLog(directory: dir)
        log.record(.navOpen(.advanced, from: .settings))
        let row = DebugLogClearRow(log: log, cleared: false)
        XCTAssertFalse(row.isEmpty)
        XCTAssertFalse(row.disabled)
        XCTAssertEqual(row.accessibilityLabel, "清空调试记录")
    }

    /// Cleared: 「已清空」, and nothing is left to clear.
    func testAfterClearingTheRowIsOffAndSaysCleared() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apptests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = FileDebugLog(directory: dir)
        log.record(.navOpen(.advanced, from: .settings))
        log.clear()
        let row = DebugLogClearRow(log: log, cleared: true)
        XCTAssertTrue(row.cleared)
        XCTAssertTrue(row.disabled)
        XCTAssertEqual(row.accessibilityLabel, "没有调试记录")
    }

    /// Outside TestFlight there is no log: the row would have nothing (and is not shown).
    func testNoLogIsEmpty() {
        XCTAssertTrue(DebugLogClearRow(log: NoDebugLog(), cleared: false).disabled)
    }
}
