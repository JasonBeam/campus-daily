import XCTest
import Foundation
import Core
import CoreTestSupport

/// 高级 › 导出调试记录: the whole log as one UTF-8 text file in a folder of its own.
final class DebugLogExportTests: XCTestCase {
    var base: URL!
    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_925_665)) // 2026-11-06 00:41:05 UTC
    let utc = TimeZone(identifier: "UTC")!
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    override func setUp() { base = DebugLogTesting.temporaryDirectory() }
    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    var exports: URL { DebugLogExport.directory(in: base) }
    func fileLog() -> FileDebugLog {
        FileDebugLog(directory: FileDebugLog.directory(in: base), now: clock.function, timeZone: utc)
    }
    func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: exports.path)) ?? []).sorted()
    }

    func testTheFolderIsItsOwn() {
        XCTAssertEqual(DebugLogExport.directory(in: URL(fileURLWithPath: "/tmp/x")).path, "/tmp/x/DebugLogExport")
    }

    func testTheFileNameIsTheLocalDateAndMinute() {
        XCTAssertEqual(DebugLogExport.fileName(at: clock.now, timeZone: shanghai), "校日常调试记录 2026-11-06 0841.txt")
        XCTAssertEqual(DebugLogExport.fileName(at: clock.now, timeZone: utc), "校日常调试记录 2026-11-06 0041.txt")
    }

    func testTheFileNameIsZeroPaddedInTheGivenTimeZone() {
        let date = Date(timeIntervalSince1970: 1_767_294_240) // 2026-01-01 19:04 UTC
        XCTAssertEqual(DebugLogExport.fileName(at: date, timeZone: shanghai), "校日常调试记录 2026-01-02 0304.txt")
        XCTAssertEqual(DebugLogExport.fileName(at: date, timeZone: utc), "校日常调试记录 2026-01-01 1904.txt")
    }

    func testTheTextIsEveryLineInOrder() {
        XCTAssertEqual(DebugLogExport.text(["a b", "c d"]), "a b\nc d\n")
        XCTAssertEqual(DebugLogExport.text([]), "")
    }

    /// Every line, not the newest hundred: oldest first, as UTF-8, named for the time of the export.
    func testTheFileHoldsTheWholeLog() throws {
        let log = fileLog()
        for i in 0 ..< 250 {
            log.record(.navOpen(i.isMultiple(of: 2) ? .home : .settings, from: .tab))
            clock.advance(1)
        }
        let url = try XCTUnwrap(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: shanghai))
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path, exports.standardizedFileURL.path)
        XCTAssertEqual(url.lastPathComponent, DebugLogExport.fileName(at: clock.now, timeZone: shanghai))
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = log.lines()
        XCTAssertEqual(lines.count, 250)
        XCTAssertEqual(text, lines.joined(separator: "\n") + "\n")
        XCTAssertTrue(text.hasPrefix("11-06 00:41:05 nav.open page=home from=tab\n"))
    }

    /// A line only queued (`record` never waits) is in the file: the export flushes first.
    func testALineJustRecordedIsIncluded() throws {
        let queue = DispatchQueue(label: "test.debuglog.export")
        let log = FileDebugLog(directory: FileDebugLog.directory(in: base), now: clock.function, timeZone: utc, queue: queue)
        log.record(.navOpen(.advanced, from: .settings))
        let url = try XCTUnwrap(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: utc))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "11-06 00:41:05 nav.open page=advanced from=settings\n")
    }

    func testAnEmptyLogExportsNothing() {
        XCTAssertNil(DebugLogExport.write(fileLog(), into: exports, now: clock.now, timeZone: utc))
        XCTAssertEqual(files(), [])
    }

    /// Outside TestFlight there is no log to export, whatever is on disk.
    func testNoTestFlightLogExportsNothing() {
        XCTAssertNil(DebugLogExport.write(NoDebugLog(), into: exports, now: clock.now, timeZone: utc))
        let appStore = LaunchDebugLog(applicationSupport: base, now: clock.function)
        appStore.record(.navOpen(.home, from: .launch))
        appStore.resolve(.appStore)
        XCTAssertNil(DebugLogExport.write(appStore, into: exports, now: clock.now, timeZone: utc))
        let unresolved = LaunchDebugLog(applicationSupport: base, now: clock.function)
        unresolved.record(.navOpen(.home, from: .launch))
        XCTAssertNil(DebugLogExport.write(unresolved, into: exports, now: clock.now, timeZone: utc))
        XCTAssertEqual(files(), [])
    }

    func testATestFlightLaunchLogExports() throws {
        let log = LaunchDebugLog(applicationSupport: base, now: clock.function)
        log.record(.navOpen(.home, from: .launch))
        log.resolve(.testFlight)
        let url = try XCTUnwrap(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: utc))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).hasSuffix("nav.open page=home from=launch\n"))
    }

    /// Only the newest export is ever left behind.
    func testTheNextExportRemovesTheOldFile() throws {
        let log = fileLog()
        log.record(.navOpen(.home, from: .launch))
        let first = try XCTUnwrap(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: utc))
        clock.advance(120)
        log.record(.navOpen(.settings, from: .tab))
        let second = try XCTUnwrap(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: utc))
        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(files(), [second.lastPathComponent])
    }

    func testAnEmptyLogStillRemovesTheOldFile() throws {
        let log = fileLog()
        log.record(.navOpen(.home, from: .launch))
        _ = try XCTUnwrap(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: utc))
        log.clear()
        XCTAssertNil(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: utc))
        XCTAssertEqual(files(), [])
    }

    /// The share sheet finished: the file goes.
    func testRemoveDeletesTheExport() throws {
        let log = fileLog()
        log.record(.navOpen(.home, from: .launch))
        _ = try XCTUnwrap(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: utc))
        DebugLogExport.remove(in: exports)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exports.path))
        DebugLogExport.remove(in: exports) // nothing there: no harm
    }

    /// Exporting writes nothing new to the log.
    func testExportingRecordsNothing() throws {
        let log = fileLog()
        log.record(.navOpen(.home, from: .launch))
        _ = try XCTUnwrap(DebugLogExport.write(log, into: exports, now: clock.now, timeZone: utc))
        XCTAssertEqual(log.lines().count, 1)
    }
}
