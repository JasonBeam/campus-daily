//
//  LaundryPaymentWindowRunnerTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
import UIKit
@testable import XiaoRiChang

/// The background task behind 立刻洗衣's window: refused means nothing runs; it ends exactly
/// once (iOS ending it, the 45 s deadline or a stop), an old run never ends a new one, it never
/// begins twice, and ending it cancels the read in progress instead of waiting for it.
@MainActor
final class LaundryPaymentWindowRunnerTests: XCTestCase {
    @MainActor final class FakeSystem {
        var grant = true
        var begun = 0
        var ended: [UIBackgroundTaskIdentifier] = []
        var expirations: [@MainActor @Sendable () -> Void] = []
        /// Seconds asked of `sleep`: the deadline's 45, then the ticks' 1 s.
        var deadlineSleeps = true

        var system: LaundryPaymentWindowRunner.System {
            LaundryPaymentWindowRunner.System(
                begin: { [unowned self] expired in
                    guard self.grant else { return nil }
                    self.begun += 1; self.expirations.append(expired)
                    return UIBackgroundTaskIdentifier(rawValue: self.begun)
                },
                end: { [unowned self] in self.ended.append($0) },
                sleep: { [deadlineSleeps] seconds in
                    if seconds >= LaundryPaymentWindowRunner.duration {
                        if deadlineSleeps { try await Task.sleep(for: .seconds(3600)) }
                        return
                    }
                    try await Task.sleep(for: .milliseconds(10))
                })
        }
    }

    func settle(_ ms: Int = 100) async { try? await Task.sleep(for: .milliseconds(ms)) }

    func testDeniedRunsNothing() async {
        let fake = FakeSystem(); fake.grant = false
        let runner = LaundryPaymentWindowRunner(system: fake.system)
        var ticks = 0, stops = 0
        let granted = runner.start(tick: { ticks += 1; return true }, onStop: { stops += 1 })
        await settle()
        XCTAssertFalse(granted)
        XCTAssertFalse(runner.isActive)
        XCTAssertEqual(ticks, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertEqual(fake.ended, [])
    }

    func testTicksWhileActive() async {
        let fake = FakeSystem()
        let runner = LaundryPaymentWindowRunner(system: fake.system)
        var ticks = 0
        XCTAssertTrue(runner.start(tick: { ticks += 1; return true }, onStop: {}))
        await settle()
        XCTAssertGreaterThan(ticks, 0)
        XCTAssertTrue(runner.isActive)
        runner.stop()
        XCTAssertFalse(runner.isActive)
    }

    func testExpirationEndsExactlyOnce() async {
        let fake = FakeSystem()
        let runner = LaundryPaymentWindowRunner(system: fake.system)
        var stops = 0
        _ = runner.start(tick: { true }, onStop: { stops += 1 })
        fake.expirations[0]()
        fake.expirations[0]()
        runner.stop()
        await settle()
        XCTAssertEqual(fake.ended.count, 1)
        XCTAssertEqual(stops, 1)
        XCTAssertFalse(runner.isActive)
    }

    func testDeadlineEndsOnce() async {
        let fake = FakeSystem(); fake.deadlineSleeps = false
        let runner = LaundryPaymentWindowRunner(system: fake.system)
        var stops = 0
        _ = runner.start(tick: { true }, onStop: { stops += 1 })
        await settle()
        XCTAssertFalse(runner.isActive)
        XCTAssertEqual(fake.ended.count, 1)
        XCTAssertEqual(stops, 1)
    }

    func testTickSayingStopEndsOnce() async {
        let fake = FakeSystem()
        let runner = LaundryPaymentWindowRunner(system: fake.system)
        var stops = 0
        _ = runner.start(tick: { false }, onStop: { stops += 1 })
        await settle()
        XCTAssertFalse(runner.isActive)
        XCTAssertEqual(fake.ended.count, 1)
        XCTAssertEqual(stops, 1)
    }

    func testOldRunNeverEndsNewOne() async {
        let fake = FakeSystem()
        let runner = LaundryPaymentWindowRunner(system: fake.system)
        _ = runner.start(tick: { true }, onStop: {})
        runner.stop()
        var stops = 0
        XCTAssertTrue(runner.start(tick: { true }, onStop: { stops += 1 }))
        fake.expirations[0]()
        await settle()
        XCTAssertTrue(runner.isActive, "the first run's expiry is not the second's")
        XCTAssertEqual(fake.ended.count, 1)
        XCTAssertEqual(stops, 0)
        runner.stop()
    }

    func testNeverBeginsTwice() {
        let fake = FakeSystem()
        let runner = LaundryPaymentWindowRunner(system: fake.system)
        XCTAssertTrue(runner.start(tick: { true }, onStop: {}))
        XCTAssertFalse(runner.start(tick: { true }, onStop: {}))
        XCTAssertEqual(fake.begun, 1)
        runner.stop()
    }

    /// Ending the window doesn't wait for a long read: the read is cancelled and finishes itself.
    func testStopCancelsTheReadInProgress() async {
        let fake = FakeSystem()
        let runner = LaundryPaymentWindowRunner(system: fake.system)
        var cancelled = false, entered = false
        _ = runner.start(tick: {
            entered = true
            try? await Task.sleep(for: .seconds(60))
            cancelled = Task.isCancelled
            return true
        }, onStop: {})
        while !entered { await Task.yield() }
        fake.expirations[0]()
        XCTAssertEqual(fake.ended.count, 1, "ended at once")
        await settle()
        XCTAssertTrue(cancelled)
    }
}
