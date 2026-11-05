import XCTest
import Foundation
import Core
import CoreTestSupport

/// The last check before a line is kept or sent.
final class DebugLogScreenTests: XCTestCase {
    func testTheLinesTheLogWritesPass() {
        for line in [
            "10-30 04:00:00 shower.phase from=idle to=authorizing",
            "10-30 04:00:01 http lxt6 POST host=lxt6 name=authorize status=200 ms=153 code=0",
            "10-30 04:00:02 http ecykt POST host=ecykt name=csalogintoken status=200 ms=88",
            "10-30 04:00:03 shower.action start machine=m:3fa2c1",
            "10-30 04:00:04 lxt.settle ok fen=163",
            "10-30 04:00:05 school.credentialExpired kind=card ageMinutes=152 aliveMinutes=92",
        ] {
            XCTAssertTrue(DebugLogScreen.isSafe(line), line)
        }
    }

    func testAnythingLikeAnIdACredentialOrAServersSentenceFails() {
        for line in [
            "x studentId 2099123456",
            "x 12345678",
            "x deadbeefdeadbeef",
            "x DEADBEEFDEADBEEF00",
            "x Bearer abc",
            "x bearer abc",
            "x token=abc",
            "x acc_token abc",
            "x Cookie: a=b",
            "x password",
            "x secret",
            "x sid=1",
            "x ticket=ST-1",
            "lxt.settle failed 重复结算",
        ] {
            XCTAssertFalse(DebugLogScreen.isSafe(line), line)
        }
    }
}

/// How the log rides along in a feedback message (AirFeedback has no attachment field).
final class DebugLogReportTests: XCTestCase {
    func line(_ i: Int) -> String { "10-30 04:\(String(format: "%02d", i % 60)):00 nav.open page=home from=tab n=\(i)" }

    func testNoLinesLeaveTheTextAsItIs() {
        XCTAssertEqual(DebugLogReport.message("洗衣机扫不出来", lines: []), "洗衣机扫不出来")
    }

    func testTheLinesFollowTheTextUnderAHeader() {
        XCTAssertEqual(DebugLogReport.message("热水没开", lines: ["a b", "c d"]),
                       "热水没开\n\n— 调试记录（测试版，最近 2 条）—\na b\nc d")
        XCTAssertEqual(DebugLogReport.message("", lines: ["a b"]), "— 调试记录（测试版，最近 1 条）—\na b",
                       "screenshots only: just the log")
    }

    /// Short lines, so a hundred fit in 4000: the count, not the length, is what cuts here.
    func testAtMostTheNewestHundred() {
        let short = { (i: Int) in "x n=\(i)" }
        let lines = (0 ..< 150).map(short)
        let message = DebugLogReport.message("反馈", lines: lines)
        XCTAssertEqual(DebugLogReport.maxLines, 100)
        XCTAssertTrue(message.contains("最近 100 条"))
        XCTAssertFalse(message.contains("n=49\n"))
        XCTAssertTrue(message.contains(short(50) + "\n"))
        XCTAssertTrue(message.hasSuffix(short(149)))
    }

    func testTextAndLogStayWithinFourThousandAndTheOldestGoFirst() {
        let text = String(repeating: "字", count: 3_700)
        let lines = (0 ..< 100).map(line)
        let message = DebugLogReport.message(text, lines: lines)
        XCTAssertLessThanOrEqual(message.utf16.count, FeedbackDraft.maximumCharacters)
        XCTAssertTrue(message.hasPrefix(text))
        XCTAssertTrue(message.hasSuffix(line(99)))
        let kept = message.components(separatedBy: "\n").filter { $0.contains("nav.open") }
        XCTAssertEqual(kept, Array(lines.suffix(kept.count)), "a run of the newest lines")
        XCTAssertTrue(message.contains("最近 \(kept.count) 条"))
        XCTAssertNil(FeedbackDraft.issue(message: message, imageCount: 0))
    }

    func testAFullTextGoesAlone() {
        let text = String(repeating: "字", count: FeedbackDraft.maximumCharacters)
        XCTAssertEqual(DebugLogReport.message(text, lines: (0 ..< 5).map(line)), text)
    }

    func testAnUnsafeLineIsLeftOut() {
        let message = DebugLogReport.message("反馈", lines: ["a ok", "b 12345678", "c ok"])
        XCTAssertFalse(message.contains("12345678"))
        XCTAssertTrue(message.contains("最近 2 条"))
    }
}

/// Which log the app gets at launch.
final class DebugLogLaunchTests: XCTestCase {
    var base: URL!
    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_332_800))
    override func setUp() { base = DebugLogTesting.temporaryDirectory() }
    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    var folder: URL { FileDebugLog.directory(in: base) }

    func testNotTestFlightKeepsNothingAndCreatesNothing() throws {
        let log = DebugLogLaunch.sink(isTestFlight: false, applicationSupport: base, now: clock.function)
        XCTAssertFalse(log.isEnabled)
        log.record(.navOpen(.home, from: .launch))
        XCTAssertEqual(log.lines(), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    }

    /// An App Store build installed over a TestFlight one: the old log goes at its first launch.
    func testNotTestFlightDeletesALogLeftByATestFlightBuild() {
        let old = FileDebugLog(directory: folder, now: clock.function)
        old.record(.navOpen(.home, from: .launch))
        old.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        _ = DebugLogLaunch.sink(isTestFlight: false, applicationSupport: base, now: clock.function)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testTestFlightKeepsTheLogInItsFolderAndDropsWeekOldLines() {
        let old = FileDebugLog(directory: folder, now: clock.function)
        old.record(.navOpen(.home, from: .launch))
        old.flush()
        clock.advance(8 * 24 * 3600)
        let log = DebugLogLaunch.sink(isTestFlight: true, applicationSupport: base, now: clock.function)
        XCTAssertTrue(log.isEnabled)
        XCTAssertEqual(log.lines(), [], "a week-old line goes at launch")
        log.record(.navOpen(.settings, from: .tab))
        XCTAssertEqual(log.lines().count, 1)
        XCTAssertEqual((log as? FileDebugLog)?.directory.standardizedFileURL, folder.standardizedFileURL)
    }

    func testNoFolderNoLog() {
        XCTAssertFalse(DebugLogLaunch.sink(isTestFlight: true, applicationSupport: nil).isEnabled)
    }

    func testNoDebugLogKeepsNothing() {
        let log = NoDebugLog()
        log.record(.navOpen(.home, from: .launch))
        XCTAssertFalse(log.isEnabled)
        XCTAssertEqual(log.lines(), [])
    }
}

/// Every request line also reaches the debug log, as known values only.
final class DebugHTTPLogSinkTests: XCTestCase {
    func testARequestLineReachesTheLogAndTheNextSink() {
        let log = RecordingDebugLog()
        let next = RecordingLogSink()
        let entry = HTTPLogEntry(service: .ecykt, method: "POST", host: "ecykt.gdbu.edu.cn", name: "S1234567",
                                 status: 200, milliseconds: 42, code: "0", error: nil)
        DebugHTTPLogSink(log, next: next).record(entry)
        XCTAssertEqual(next.entries, [entry])
        XCTAssertEqual(log.events.count, 1)
        guard case .http(let h)? = log.events.first else { return XCTFail() }
        XCTAssertEqual(h.name, .other, "a name off the list (a path part) is not kept")
        XCTAssertEqual(log.lines().first?.contains("S1234567"), false)
    }

    func testNothingGoesToADisabledLog() {
        let next = RecordingLogSink()
        let entry = HTTPLogEntry(service: .ujing, method: "GET", host: "phoenix.ujing.online", name: "orderDetail",
                                 status: 200, milliseconds: 1, code: nil, error: nil)
        DebugHTTPLogSink(NoDebugLog(), next: next).record(entry)
        XCTAssertEqual(next.entries, [entry])
    }
}
