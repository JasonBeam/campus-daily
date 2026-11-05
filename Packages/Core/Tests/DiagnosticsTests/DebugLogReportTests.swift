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

/// What StoreKit says about the install, for `DebugLogLaunch.decision`.
struct FakeInstallSource: InstallEnvironmentSource {
    enum Answer: Sendable { case environment(InstallEnvironment), failure, hang }
    let answer: Answer
    struct Failure: Error {}
    func environment() async throws -> InstallEnvironment {
        switch answer {
        case .environment(let e): return e
        case .failure: throw Failure()
        case .hang:
            // Ignores cancellation, as StoreKit may: the timeout must not wait for it.
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            return .sandbox
        }
    }
}

/// TestFlight is what StoreKit's app transaction says: `sandbox`. Only a positive `production`
/// is the App Store; anything else is left undecided (no log, nothing deleted).
final class DebugLogDecisionTests: XCTestCase {
    func decide(_ answer: FakeInstallSource.Answer, timeout: TimeInterval = 1) async -> DebugLogDecision {
        await DebugLogLaunch.decision(from: FakeInstallSource(answer: answer), timeout: timeout)
    }

    func testSandboxIsTestFlight() async {
        let d = await decide(.environment(.sandbox))
        XCTAssertEqual(d, .testFlight)
    }

    func testProductionIsTheAppStore() async {
        let d = await decide(.environment(.production))
        XCTAssertEqual(d, .appStore)
    }

    func testXcodeAndUnknownAreUndecided() async {
        let x = await decide(.environment(.xcode))
        let o = await decide(.environment(.other))
        XCTAssertEqual(x, .undetermined)
        XCTAssertEqual(o, .undetermined)
    }

    func testAnErrorIsUndecided() async {
        let d = await decide(.failure)
        XCTAssertEqual(d, .undetermined)
    }

    func testATimeoutIsUndecidedAndDoesNotWaitForStoreKit() async {
        let start = Date()
        let d = await decide(.hang, timeout: 0.1)
        XCTAssertEqual(d, .undetermined)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testTheLaunchTimeoutIsFiveSeconds() {
        XCTAssertEqual(DebugLogLaunch.timeout, 5)
    }
}

/// The log the app gets at launch: it holds lines in memory until the install is known.
final class DebugLogLaunchTests: XCTestCase {
    var base: URL!
    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_332_800))
    override func setUp() { base = DebugLogTesting.temporaryDirectory() }
    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    var folder: URL { FileDebugLog.directory(in: base) }
    func launchLog(_ support: URL? = nil, limit: Int = LaunchDebugLog.bufferLimit) -> LaunchDebugLog {
        LaunchDebugLog(applicationSupport: support ?? base, now: clock.function, bufferLimit: limit)
    }
    func leaveOldLog() {
        let old = FileDebugLog(directory: folder, now: clock.function)
        old.record(.navOpen(.home, from: .launch))
        old.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testBeforeTheAnswerItIsOffAndWritesNothing() throws {
        let log = launchLog()
        log.record(.navOpen(.home, from: .launch))
        XCTAssertFalse(log.isEnabled, "the feedback toggle and clear row stay hidden")
        XCTAssertNil(log.decision)
        XCTAssertEqual(log.lines(), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    }

    func testTestFlightReplaysTheHeldLinesWithTheirTimes() {
        let log = launchLog()
        log.record(.navOpen(.home, from: .launch))
        clock.advance(2)
        log.record(.navOpen(.settings, from: .tab))
        clock.advance(10)
        log.resolve(.testFlight)
        XCTAssertTrue(log.isEnabled)
        log.flush()
        let lines = log.lines()
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("nav.open"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines[1].contains("settings"), lines.joined(separator: "\n"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: FileDebugLog(directory: folder).eventsFile.path))
        log.record(.navOpen(.records, from: .tab))
        log.flush()
        XCTAssertEqual(log.lines().count, 3)
    }

    func testTheHeldLinesAreBounded() {
        let log = launchLog(limit: 5)
        for _ in 0..<8 { log.record(.navOpen(.home, from: .launch)) }
        log.resolve(.testFlight)
        log.flush()
        XCTAssertEqual(log.lines().count, 5)
        XCTAssertEqual(LaunchDebugLog.bufferLimit, 200)
    }

    func testTestFlightKeepsTheOldLogAndDropsWeekOldLines() {
        leaveOldLog()
        clock.advance(8 * 24 * 3600)
        let log = launchLog()
        log.resolve(.testFlight)
        log.flush()
        XCTAssertEqual(log.lines(), [], "a week-old line goes at launch")
        log.record(.navOpen(.settings, from: .tab))
        log.flush()
        XCTAssertEqual(log.lines().count, 1)
    }

    func testTheAppStoreDropsTheHeldLinesAndDeletesALeftoverLog() throws {
        leaveOldLog()
        let log = launchLog()
        log.record(.navOpen(.home, from: .launch))
        log.resolve(.appStore)
        XCTAssertFalse(log.isEnabled)
        log.record(.navOpen(.settings, from: .tab))
        XCTAssertEqual(log.lines(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    }

    /// A timeout, an error or an Xcode run: no log, and a TestFlight log already there stays.
    func testUndecidedKeepsNothingAndDeletesNothing() {
        leaveOldLog()
        let log = launchLog()
        log.record(.navOpen(.home, from: .launch))
        log.resolve(.undetermined)
        XCTAssertFalse(log.isEnabled)
        XCTAssertEqual(log.lines(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(FileDebugLog(directory: folder, now: clock.function).lines().count, 1, "the old lines are untouched")
    }

    func testOnlyTheFirstAnswerCounts() {
        leaveOldLog()
        let log = launchLog()
        log.resolve(.undetermined)
        log.resolve(.appStore)
        log.resolve(.testFlight)
        XCTAssertEqual(log.decision, .undetermined)
        XCTAssertFalse(log.isEnabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    /// A sign-out before the answer clears what was held and, on TestFlight, what was on disk.
    func testAClearBeforeTheAnswerReachesTheFile() {
        leaveOldLog()
        let log = launchLog()
        log.record(.navOpen(.home, from: .launch))
        log.clear()
        log.record(.navOpen(.settings, from: .tab))
        log.resolve(.testFlight)
        log.flush()
        XCTAssertEqual(log.lines().count, 1)
        XCTAssertTrue(log.lines()[0].contains("settings"))
    }

    func testNoFolderNoLog() {
        let log = LaunchDebugLog(applicationSupport: nil)
        log.resolve(.testFlight)
        XCTAssertFalse(log.isEnabled)
    }

    func testStartAsksTheSourceAndWaitingSeesTheAnswer() async {
        let log = DebugLogLaunch.start(applicationSupport: base, source: FakeInstallSource(answer: .environment(.sandbox)),
                                       timeout: 1, now: clock.function)
        await log.waitUntilResolved()
        XCTAssertEqual(log.decision, .testFlight)
        XCTAssertTrue(log.isEnabled)
    }

    func testStartOnAHangingSourceEndsUndecided() async {
        leaveOldLog()
        let log = DebugLogLaunch.start(applicationSupport: base, source: FakeInstallSource(answer: .hang),
                                       timeout: 0.1, now: clock.function)
        await log.waitUntilResolved()
        XCTAssertEqual(log.decision, .undetermined)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testNoDebugLogKeepsNothing() async {
        let log = NoDebugLog()
        log.record(.navOpen(.home, from: .launch))
        await log.waitUntilResolved()
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
