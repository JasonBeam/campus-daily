//
//  LeaseWaitBudgetTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
@testable import Core
import CoreTestSupport

/// How long the widget and a login wait for the lease, in wall-clock time with the lock waits
/// included: the widget stays within its few seconds, a login shows busy within one lock wait
/// when the lock is stuck and at its `leaseWait` while the other process reads.
final class LeaseWaitBudgetTests: XCTestCase {
    /// Another descriptor holding the lease file's exclusive lock until `unlock()` (the other
    /// process suspended inside a step).
    final class Holder: @unchecked Sendable {
        let fd: Int32
        init(_ url: URL) throws {
            fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileLocking) }
        }
        func unlock() { flock(fd, LOCK_UN); close(fd) }
    }

    func stack(_ h: Harness, role: String, leaseWait: TimeInterval) -> SchoolRefreshStack {
        SchoolRefreshStack(store: h.store, http: h.server.makeClient(), role: role, leaseWait: leaseWait,
                           leaseFile: h.store.leaseFile, diagnostic: { _ in })
    }

    func seconds(since start: Date) -> TimeInterval { Date().timeIntervalSince(start) }

    /// The widget's whole wait before a timeline with the lock stuck: the pending clear's short
    /// wait, then one lock wait for the lease, which ends it (not one per try, as before).
    func testAWidgetRefreshWithTheLockHeldElsewhereEndsWithinItsBudget() async throws {
        let h = Harness()
        try h.signedIn()
        let holder = try Holder(h.store.leaseFile.url)
        defer { holder.unlock() }
        let widget = stack(h, role: "widget", leaseWait: SchoolRefreshStack.widgetLeaseWait).refresher

        let started = Date()
        await widget.finishPendingClear(lockWait: SchoolRefreshStack.widgetPendingClearWait)
        let report = await widget.refresh(inBackground: true)
        let took = seconds(since: started)

        XCTAssertTrue(report.leaseBusy, "nothing read without the lease")
        XCTAssertLessThan(took, SchoolRefreshStack.widgetPendingClearWait + LeaseFile.defaultLockWait + 0.75,
                          "one lock wait for the lease, not one per try")
        XCTAssertLessThan(took, SchoolRefreshStack.widgetLeaseWait, "within the widget's lease wait")
        XCTAssertEqual(h.server.requests.count, 0, "nothing sent")
    }

    /// The app reading (its live lease, the lock free): the widget gives up once `leaseWait`
    /// has gone by on the clock.
    func testAWidgetWaitingForTheAppsReadStopsAtItsLeaseWait() async throws {
        let h = Harness()
        try h.signedIn()
        XCTAssertTrue(RefreshLease(file: h.store.leaseFile, owner: "app-1").acquire())
        let widget = stack(h, role: "widget", leaseWait: 2).refresher

        let started = Date()
        let report = await widget.refresh(inBackground: true)
        let took = seconds(since: started)

        XCTAssertTrue(report.leaseBusy)
        XCTAssertGreaterThanOrEqual(took, 1.9, "it did wait for the app's read")
        XCTAssertLessThan(took, 2.75, "and stopped at its lease wait")
    }

    /// A login while the lock is stuck shows busy after one lock wait, not after `leaseWait`
    /// tries of one lock wait each (about 48 s before).
    func testALoginWhileTheLockIsStuckShowsBusyWithinOneLockWait() async throws {
        let h = Harness()
        let holder = try Holder(h.store.leaseFile.url)
        defer { holder.unlock() }
        let app = stack(h, role: "app", leaseWait: SchoolRefreshStack.appLeaseWait).refresher

        let started = Date()
        do {
            _ = try await app.holdingLease { _ in XCTFail("the body never runs without the lease") }
            XCTFail("busy")
        } catch let failure as SchoolLoginFailure {
            XCTAssertEqual(failure, .busy)
        }
        XCTAssertLessThan(seconds(since: started), LeaseFile.defaultLockWait + 0.75)
    }

    /// A login while the widget reads waits for it up to `leaseWait` on the clock, then is busy.
    func testALoginWhileTheWidgetReadsShowsBusyAtItsLeaseWait() async throws {
        let h = Harness()
        XCTAssertTrue(RefreshLease(file: h.store.leaseFile, owner: "widget-1").acquire())
        let app = stack(h, role: "app", leaseWait: 1.5).refresher

        let started = Date()
        do {
            _ = try await app.holdingLease { _ in XCTFail("the body never runs without the lease") }
            XCTFail("busy")
        } catch let failure as SchoolLoginFailure {
            XCTAssertEqual(failure, .busy)
        }
        let took = seconds(since: started)
        XCTAssertGreaterThanOrEqual(took, 1.4)
        XCTAssertLessThan(took, 2.25)
    }
}
