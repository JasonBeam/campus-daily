//
//  WidgetDebugLogTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
@testable import Core
import CoreTestSupport

/// The widget's lines in the App Group: written only with the app's salt, kept 7 days and at
/// most `maxLines`, read into the app's log by time, emptied with it, and never waited for by
/// the caller (a lock held elsewhere drops the line after a short bound).
final class WidgetDebugLogTests: XCTestCase {
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_790_000_000)
        var now: Date { lock.withLock { value } }
        func advance(_ s: TimeInterval) { lock.withLock { value += s } }
    }

    var dir: URL!
    var group: URL { dir.appendingPathComponent("group/DebugLog", isDirectory: true) }

    override func setUp() { super.setUp(); dir = DebugLogTesting.temporaryDirectory() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    func app(_ clock: Clock) -> FileDebugLog {
        let log = FileDebugLog(directory: FileDebugLog.directory(in: dir.appendingPathComponent("app")), shared: group,
                               now: { clock.now }, timeZone: TimeZone(identifier: "UTC")!)
        log.shareSalt()
        log.flush()
        return log
    }

    func testLinesAreMergedByTimeAndClearedWithTheAppsLog() {
        let clock = Clock()
        let app = app(clock)
        let widget = WidgetDebugLog(folder: group, now: { clock.now })
        app.record(.topUpWeChat(opened: true)); app.flush()
        clock.advance(1)
        widget.record(.schoolWebLogin(.opened)); widget.flush()
        clock.advance(1)
        app.record(.topUpWeChat(opened: false)); app.flush()
        XCTAssertEqual(app.lines().map { String($0.dropFirst(15)) },
                       ["topUp.weChat opened=yes", "school.webLogin opened", "topUp.weChat opened=no"])

        app.clear()
        XCTAssertEqual(app.lines(), [])
        app.flush()
        XCTAssertTrue(widget.isEnabled, "a new salt is shared at once")
        widget.record(.schoolWebLogin(.cancelled)); widget.flush()
        XCTAssertEqual(app.lines().count, 1, "the widget goes on with the new salt")
    }

    func testOldLinesGoAndTheFileStaysWithinItsCap() {
        let clock = Clock()
        let app = app(clock)
        let widget = WidgetDebugLog(folder: group, now: { clock.now }, maxLines: 3)
        widget.record(.schoolWebLogin(.opened)); widget.flush()
        clock.advance(WidgetDebugLog.maxAge + 1)
        XCTAssertEqual(app.lines(), [], "not shown once a week old")
        for _ in 0..<4 { widget.record(.schoolWebLogin(.completed)); widget.flush() }
        let lines = app.lines()
        XCTAssertEqual(lines.count, 3, "at most maxLines")
        XCTAssertTrue(lines.allSatisfy { $0.hasSuffix("school.webLogin completed") }, "the week-old line went")
    }

    func testAHeldLockDropsTheLineWithoutHoldingTheCaller() throws {
        let clock = Clock()
        let app = app(clock)
        let widget = WidgetDebugLog(folder: group, now: { clock.now })
        let fd = open(group.appendingPathComponent("widget.lock").path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)

        let started = Date()
        widget.record(.schoolWebLogin(.opened))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.05, "record only queues the line")
        widget.flush()
        XCTAssertLessThan(Date().timeIntervalSince(started), WidgetDebugLog.lockWait + 0.3, "a short bound")
        XCTAssertEqual(app.lines(), [], "dropped, not written beside the lock")

        flock(fd, LOCK_UN); close(fd)
        widget.record(.schoolWebLogin(.opened)); widget.flush()
        XCTAssertEqual(app.lines().count, 1)
    }

    func testAnAppStoreLaunchDeletesTheWidgetsFolder() {
        let clock = Clock()
        _ = app(clock)
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.path))
        let launch = LaunchDebugLog(applicationSupport: dir.appendingPathComponent("app"), shared: group)
        launch.resolve(.appStore)
        launch.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.path))
        XCTAssertFalse(WidgetDebugLog(folder: group).isEnabled)
    }

    // MARK: The app removing while the widget writes

    var log: URL { group.appendingPathComponent(WidgetDebugLog.logName) }

    /// A clear while the widget is inside its write: the removal waits for the widget's lock,
    /// and the line the widget was writing (with the old salt) is not kept either.
    func testAClearDuringAWriteInFlightLeavesNoOldLines() {
        let clock = Clock()
        let app = app(clock)
        let old = WidgetDebugLog(folder: group, now: { clock.now })
        old.record(.schoolWebLogin(.opened)); old.flush()
        XCTAssertEqual(app.lines().count, 1)

        let entered = DispatchSemaphore(value: 0), go = DispatchSemaphore(value: 0)
        let widget = WidgetDebugLog(folder: group, now: { clock.now }, queue: DispatchQueue(label: "widget-test"),
                                    beforeLock: nil, insideLock: { entered.signal(); go.wait() })
        widget.record(.schoolWebLogin(.completed))
        entered.wait()
        app.clear()
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.path), "the removal waits for the write in flight")
        go.signal()
        widget.flush(); app.flush()

        XCTAssertEqual(app.lines(), [], "neither the old line nor the one in flight")
        XCTAssertTrue(widget.isEnabled, "a new salt")
    }

    /// The salt changed between the widget reading it and taking the lock: the line, tagged with
    /// the old salt, is dropped (and the cleared lines are not written back).
    func testASaltReplacedBeforeTheLockDropsTheLine() {
        let clock = Clock()
        let app = app(clock)
        let old = WidgetDebugLog(folder: group, now: { clock.now })
        old.record(.schoolWebLogin(.opened)); old.flush()
        let widget = WidgetDebugLog(folder: group, now: { clock.now }, queue: DispatchQueue(label: "widget-test"),
                                    beforeLock: { app.clear(); app.flush() }, insideLock: nil)
        widget.record(.schoolWebLogin(.completed)); widget.flush()
        XCTAssertEqual(app.lines(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
    }

    /// The folder deleted (an App Store launch) while the widget was about to write: it is not
    /// made again, and no `widget.log` is left without a salt.
    func testTheWidgetNeverMakesTheFolderAgain() {
        let clock = Clock()
        _ = app(clock)
        let widget = WidgetDebugLog(folder: group, now: { clock.now }, queue: DispatchQueue(label: "widget-test"),
                                    beforeLock: { [group] in WidgetDebugLog.remove(.folder, in: group) }, insideLock: nil)
        widget.record(.schoolWebLogin(.opened)); widget.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.path))
    }

    // MARK: Only after the app found TestFlight

    /// No answer at launch (offline, a timeout; maybe an App Store build over a TestFlight one):
    /// the salt is taken back and the widget writes nothing; a later launch that finds
    /// TestFlight lets it write again, with the same salt, and the earlier lines are still there.
    func testAnUndeterminedLaunchStopsTheWidgetUntilTestFlightIsFound() {
        let clock = Clock()
        _ = app(clock)
        let widget = WidgetDebugLog(folder: group, now: { clock.now })
        widget.record(.schoolWebLogin(.opened)); widget.flush()

        let unknown = LaunchDebugLog(applicationSupport: dir.appendingPathComponent("app"), shared: group, now: { clock.now })
        unknown.resolve(.undetermined)
        unknown.flush()
        XCTAssertFalse(widget.isEnabled)
        let before = try? Data(contentsOf: log)
        widget.record(.schoolWebLogin(.completed)); widget.flush()
        XCTAssertEqual(try? Data(contentsOf: log), before, "nothing written")

        let found = LaunchDebugLog(applicationSupport: dir.appendingPathComponent("app"), shared: group, now: { clock.now })
        found.resolve(.testFlight)
        found.flush()
        XCTAssertTrue(widget.isEnabled)
        widget.record(.schoolWebLogin(.cancelled)); widget.flush()
        XCTAssertEqual(found.lines().map { String($0.dropFirst(15)) }, ["school.webLogin opened", "school.webLogin cancelled"])
    }

    func testATestFlightLaunchSharesTheSalt() {
        let launch = LaunchDebugLog(applicationSupport: dir.appendingPathComponent("app"), shared: group)
        launch.resolve(.testFlight)
        launch.flush()
        XCTAssertTrue(WidgetDebugLog(folder: group).isEnabled)
    }
}
