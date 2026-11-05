import XCTest
import Foundation
import Core
import CoreTestSupport

/// The TestFlight log on disk: its lines, its limits, its folder and its salt.
final class FileDebugLogTests: XCTestCase {
    var dir: URL!
    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_332_800)) // 2026-10-30 04:00:00 UTC
    let utc = TimeZone(identifier: "UTC")!

    override func setUp() { dir = DebugLogTesting.temporaryDirectory().appendingPathComponent("DebugLog", isDirectory: true) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

    func log(maxLines: Int = FileDebugLog.maxLines, maxBytes: Int = FileDebugLog.maxBytes) -> FileDebugLog {
        FileDebugLog(directory: dir, now: clock.function, timeZone: utc, maxLines: maxLines, maxBytes: maxBytes)
    }

    /// The caller never waits on the disk: with the writer busy, `record` still returns at once;
    /// `flush` then waits for the line.
    func testRecordDoesNotWaitForTheDisk() {
        let queue = DispatchQueue(label: "test.debuglog")
        let log = FileDebugLog(directory: dir, now: clock.function, timeZone: utc, queue: queue)
        let busy = DispatchSemaphore(value: 0)
        queue.async { busy.wait() }
        let returned = expectation(description: "record returned")
        DispatchQueue.global().async {
            log.record(.navOpen(.home, from: .launch))
            returned.fulfill()
        }
        wait(for: [returned], timeout: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.eventsFile.path), "not written yet: the writer is busy")
        busy.signal()
        log.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.eventsFile.path))
        XCTAssertEqual(log.lines(), ["10-30 04:00:00 nav.open page=home from=launch"])
    }

    func testTheLimitsAreAThousandLinesQuarterMegabyteAndSevenDays() {
        XCTAssertEqual(FileDebugLog.maxLines, 1000)
        XCTAssertEqual(FileDebugLog.maxBytes, 256 * 1024)
        XCTAssertEqual(FileDebugLog.maxAge, 7 * 24 * 3600)
        XCTAssertEqual(FileDebugLog.directory(in: URL(fileURLWithPath: "/x")).path, "/x/DebugLog")
    }

    func testALineIsTheTimeTheNameAndTheFields() {
        let log = log()
        XCTAssertTrue(log.isEnabled)
        log.record(.navOpen(.showerPage, from: .homeButton))
        clock.advance(61)
        log.record(.laundryPayLaunch(opened: true))
        XCTAssertEqual(log.lines(), ["10-30 04:00:00 nav.open page=showerPage from=homeButton",
                                     "10-30 04:01:01 laundry.payLaunch opened=yes"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.eventsFile.path))
        XCTAssertEqual(log.eventsFile.lastPathComponent, "events.log")
    }

    func testTheLinesAreThereAfterARelaunch() {
        let first = log()
        first.record(.schoolRefresh(.ok))
        first.flush()
        XCTAssertEqual(log().lines(), ["10-30 04:00:00 school.refresh ok"])
    }

    func testTheOldestLinesGoPastAThousand() {
        let log = log()
        for i in 0 ..< 1003 {
            log.record(.http(DebugHTTP(HTTPLogEntry(service: .ujing, method: "GET", host: "phoenix.ujing.online", name: "orderDetail",
                                                    status: 200, milliseconds: i, code: nil, error: nil))))
        }
        let lines = log.lines()
        XCTAssertEqual(lines.count, 1000)
        XCTAssertTrue(lines.first?.hasSuffix(" ms=3") ?? false, lines.first ?? "")
        XCTAssertTrue(lines.last?.hasSuffix(" ms=1002") ?? false)
        XCTAssertEqual(self.log().lines().count, 1000, "the file was cut too")
    }

    func testTheFileStaysUnderItsByteLimit() throws {
        let log = log(maxBytes: 600)
        for _ in 0 ..< 40 { log.record(.navOpen(.laundry, from: .widget)) }
        log.flush()
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: log.eventsFile.path)[.size] as? Int)
        XCTAssertLessThanOrEqual(size, 600)
        XCTAssertFalse(log.lines().isEmpty)
        XCTAssertEqual(log.lines().count, self.log(maxBytes: 600).lines().count)
    }

    func testLinesOlderThanSevenDaysGoWhenPruned() {
        let log = log()
        log.record(.navOpen(.home, from: .launch))
        clock.advance(7 * 24 * 3600 + 1)
        log.record(.navOpen(.settings, from: .tab))
        log.pruneExpired()
        XCTAssertEqual(log.lines(), ["11-06 04:00:01 nav.open page=settings from=tab"])
        XCTAssertEqual(self.log().lines().count, 1)
    }

    func testTheFolderIsKeptOutOfBackups() throws {
        let log = log()
        log.record(.navOpen(.home, from: .launch))
        log.flush()
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testATagIsTheSameForTheSameValueAndSalt() {
        let log = log()
        let a = log.tag(.machine("11223344"))
        XCTAssertNotNil(a.range(of: "^m:[0-9a-f]{6}$", options: .regularExpression), a)
        XCTAssertEqual(log.tag(.machine("aabbccdd")), log.tag(.machine("AABBCCDD")), "case variants are the same machine")
        XCTAssertNotEqual(a, log.tag(.machine("11223345")))
        XCTAssertEqual(self.log().tag(.machine("11223344")), a, "the salt is kept with the log")
        XCTAssertTrue(log.tag(DebugTag(.order, "TESTORDER0001")).hasPrefix("o:"))
        XCTAssertTrue(log.tag(DebugTag(.washer, "test-device-0001")).hasPrefix("w:"))
    }

    func testClearingRemovesTheLinesAndChangesTheSalt() {
        let log = log()
        log.record(.showerAction(.start(machine: .machine("11223344"))))
        log.flush()
        let before = log.tag(.machine("11223344"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.saltFile.path))
        log.clear()
        XCTAssertEqual(log.lines(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.eventsFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.saltFile.path))
        XCTAssertNotEqual(log.tag(.machine("11223344")), before, "a new salt: old tags no longer match")
        XCTAssertEqual(self.log().lines(), [])
    }

    func testTheSaltIsNeverInTheLines() throws {
        let log = log()
        log.record(.showerAction(.startNext(machine: .machine("11223344"))))
        log.flush()
        let salt = try Data(contentsOf: log.saltFile)
        XCTAssertEqual(salt.count, 32)
        let hex = salt.map { String(format: "%02x", $0) }.joined()
        let text = log.lines().joined(separator: "\n") + (try String(contentsOf: log.eventsFile, encoding: .utf8))
        XCTAssertTrue(DebugLogTesting.leaks([hex, salt.base64EncodedString(), String(hex.prefix(12))], in: text).isEmpty)
        XCTAssertTrue(text.contains("startNext machine=m:"))
        XCTAssertFalse(text.contains("11223344"))
    }

    /// The last check: a line that looks like an id or a credential is never kept.
    func testALineThatLooksLikeAnIdIsDropped() throws {
        let log = log()
        log.record(.http(DebugHTTP(HTTPLogEntry(service: .lxt6, method: "POST", host: "isv.lxt6.cn", name: "settle",
                                                status: 200, milliseconds: 123_456_789, code: "0", error: nil))))
        XCTAssertEqual(log.lines(), ["10-30 04:00:00 \(DebugLogScreen.dropped)"])
        XCTAssertEqual(log.droppedCount, 1)
        XCTAssertFalse(try String(contentsOf: log.eventsFile, encoding: .utf8).contains("123456789"))
    }

    /// A log that can't be written takes every line without throwing.
    func testAnUnwritableFolderIsHarmless() throws {
        let file = dir.deletingLastPathComponent().appendingPathComponent("plain-file")
        try Data("x".utf8).write(to: file)
        let log = FileDebugLog(directory: file.appendingPathComponent("DebugLog"), now: clock.function, timeZone: utc)
        for _ in 0 ..< 3 { log.record(.navOpen(.home, from: .launch)) }
        _ = log.tag(.machine("11223344"))
        log.clear()
        _ = log.lines()
    }
}
