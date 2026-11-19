import XCTest
import Core
@testable import XiaoRiChang

/// 高级 › 导出调试记录: off with nothing to export (and VoiceOver says so, as the clear row does),
/// on with lines; the line under both rows is one constant.
final class DebugLogExportRowTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("apptests-\(UUID().uuidString)", isDirectory: true) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testTheRowWordsAreFinal() {
        XCTAssertEqual(DebugLogExportRow.title, "导出调试记录")
        XCTAssertEqual(DebugLogExportRow.emptyLabel, "没有调试记录")
        XCTAssertEqual(DebugLogExportRow.emptyLabel, DebugLogClearRow.emptyLabel)
        XCTAssertEqual(DebugLogClearRow.footer, "调试记录只存在这台手机上，最多留 7 天，退出登录也会清空。导出后发给谁由你决定。")
    }

    func testAnEmptyLogDisablesTheRowAndSaysSo() {
        let row = DebugLogExportRow(log: FileDebugLog(directory: dir))
        XCTAssertTrue(row.isEmpty)
        XCTAssertTrue(row.disabled)
        XCTAssertEqual(row.accessibilityLabel, "没有调试记录")
    }

    /// A line only queued counts: the row flushes before it reads.
    func testALogWithALineJustRecordedCanBeExported() {
        let log = FileDebugLog(directory: dir)
        log.record(.navOpen(.advanced, from: .settings))
        let row = DebugLogExportRow(log: log)
        XCTAssertFalse(row.isEmpty)
        XCTAssertFalse(row.disabled)
        XCTAssertEqual(row.accessibilityLabel, "导出调试记录")
    }

    /// After 清空调试记录 both rows are off and both say so.
    func testAfterClearingBothRowsAreOff() {
        let log = FileDebugLog(directory: dir)
        log.record(.navOpen(.advanced, from: .settings))
        log.clear()
        let export = DebugLogExportRow(log: log)
        let clear = DebugLogClearRow(log: log, cleared: true)
        XCTAssertTrue(export.disabled)
        XCTAssertTrue(clear.disabled)
        XCTAssertEqual(export.accessibilityLabel, "没有调试记录")
        XCTAssertEqual(clear.accessibilityLabel, "没有调试记录")
    }

    /// Outside TestFlight there is no log: nothing to export (and the row is not shown).
    func testNoLogIsEmpty() {
        XCTAssertTrue(DebugLogExportRow(log: NoDebugLog()).disabled)
        XCTAssertNil(DebugLogExportRow.file(from: NoDebugLog(), in: dir))
    }

    /// The tap's file: the whole log, in the app's own folder under the temporary directory.
    func testTheFileIsTheWholeLog() throws {
        let log = FileDebugLog(directory: dir.appendingPathComponent("DebugLog", isDirectory: true))
        log.record(.navOpen(.advanced, from: .settings))
        let url = try XCTUnwrap(DebugLogExportRow.file(from: log, in: dir))
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "DebugLogExport")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("校日常调试记录 "))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".txt"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), log.lines().joined(separator: "\n") + "\n")
    }
}
