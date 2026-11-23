//
//  LeaseLockWaitTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
@testable import Core
import CoreTestSupport

/// The lease file's lock held by someone else for good (the widget suspended inside a step): a
/// step gives up after its bound and writes nothing, the sign-out's removal waits longer, and
/// nothing waiting for it holds a thread: the async steps suspend between tries.
final class LeaseLockWaitTests: XCTestCase {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lease-wait-\(UUID().uuidString)")
    let clock = TestClock()

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    /// Another descriptor holding the file's exclusive lock until `unlock()`.
    final class Holder: @unchecked Sendable {
        let fd: Int32
        init(_ url: URL) throws {
            fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw LeaseFile.Failure(step: "test", code: errno) }
        }
        func unlock() { flock(fd, LOCK_UN); close(fd) }
    }

    func lease(_ owner: String, wait: TimeInterval) -> RefreshLease {
        RefreshLease(file: LeaseFile(url: url, insideLock: nil, lockWait: wait), owner: owner, now: clock.function)
    }

    func testTheDefaultBoundIsTwoSeconds() {
        XCTAssertEqual(LeaseFile.defaultLockWait, 2)
        XCTAssertEqual(LeaseFile(url: url).lockWait, 2)
    }

    /// Every bounded step returns within its bound while the lock is held, and none of them
    /// writes: no lease taken, no body run, no record stored.
    func testAHeldLockMakesEveryStepGiveUpWithinTheBoundAndWriteNothing() throws {
        XCTAssertTrue(lease("app-0", wait: 1).acquire())
        lease("app-0", wait: 1).release()
        let holder = try Holder(url)
        let app = lease("app-1", wait: 0.3)

        let started = Date()
        XCTAssertFalse(app.acquire(), "no lease without the lock")
        let took = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(took, 0.25, "it did wait for the lock first")
        XCTAssertLessThan(took, 2, "and gave up within the bound")

        XCTAssertFalse(app.renew())
        XCTAssertFalse(app.holds())
        var ran = false
        XCTAssertNil(try app.withOwnership { ran = true })
        XCTAssertNil(try app.withOwnershipRetaking { ran = true })
        XCTAssertNil(app.afterLosing { ran = true })
        XCTAssertThrowsError(try app.locked { ran = true }) { error in
            XCTAssertEqual((error as? LeaseFile.Failure)?.step, "lock")
            XCTAssertEqual((error as? LeaseFile.Failure)?.code, EWOULDBLOCK)
        }
        XCTAssertFalse(ran, "no body ran without the lock")
        app.release()

        holder.unlock()
        XCTAssertNil(LeaseFile(url: url).storedOwner(), "nothing was written while the lock was held")
        XCTAssertTrue(app.acquire(), "free again once the lock is")
    }

    /// The bound ends the wait, not the lock: a lock freed within it is taken.
    func testALockFreedWithinTheBoundIsTaken() throws {
        let holder = try Holder(url)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { holder.unlock() }
        XCTAssertTrue(lease("app-1", wait: 5).acquire())
    }

    /// The async steps give up the same way, and tell a lock that stayed held from a lease
    /// that is not ours: nothing runs, nothing is written.
    func testAHeldLockMakesEveryAsyncStepGiveUpAsALockTimeout() async throws {
        XCTAssertTrue(lease("app-1", wait: 1).acquire())
        let holder = try Holder(url)
        let app = lease("app-1", wait: 0.3)

        let started = Date()
        let took = await app.acquire(waitingAtMost: 0.3)
        XCTAssertEqual(took, .lockTimeout)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.25, "it did wait for the lock first")
        let renewed = await app.renew(waitingAtMost: 0.1)
        XCTAssertFalse(renewed)
        var ran = false
        guard case .lockTimeout = try await app.withOwnership(waitingAtMost: 0.1, retaking: false, { ran = true }) else {
            return XCTFail("a lock timeout, not a lost lease")
        }
        guard case .lockTimeout = try await app.withOwnership(waitingAtMost: 0.1, retaking: true, { ran = true }) else {
            return XCTFail("a lock timeout, not a lost lease")
        }
        let wrote = try await LeaseOwnership(app).write { ran = true }
        XCTAssertNil(wrote)
        let lost = await app.afterLosing(waitingAtMost: 0.1) { ran = true }
        XCTAssertNil(lost)
        do { try await app.lockedWhenFree { ran = true }; XCTFail("locked") } catch let failure as LeaseFile.Failure {
            XCTAssertTrue(failure.isLockTimeout)
        }
        do { try await app.clear(waitingAtMost: 0.1); XCTFail("removed") } catch let failure as LeaseFile.Failure {
            XCTAssertTrue(failure.isLockTimeout)
        }
        XCTAssertThrowsError(try app.lockedIfFree { ran = true }, "no wait at all")
        XCTAssertFalse(ran, "no body ran without the lock")

        holder.unlock()
        XCTAssertEqual(LeaseFile(url: url).storedOwner(), "app-1", "nothing was written while the lock was held")
        guard case .lost = try await lease("widget-1", wait: 0.3).withOwnership(waitingAtMost: 0.3, retaking: true, { ran = true }) else {
            return XCTFail("another owner's lease: lost, as before")
        }
        XCTAssertFalse(ran)
        let mine = await app.acquire(waitingAtMost: 0.3)
        XCTAssertEqual(mine, .taken, "free again once the lock is")
    }

    /// A cancelled read (the widget past its deadline) still gives its lease back when the
    /// lock is busy for a moment: that wait is not cut short by the cancellation.
    func testACancelledTaskStillGivesTheLeaseBackAfterABriefWait() async throws {
        let widget = lease("widget-1", wait: 1)
        XCTAssertTrue(widget.acquire())
        let holder = try Holder(url)
        let release = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            await widget.release(waitingAtMost: 1)
        }
        release.cancel()
        try await Task.sleep(for: .milliseconds(100))
        holder.unlock()
        await release.value
        XCTAssertNil(LeaseFile(url: url).storedOwner(), "given back once the lock was free")
    }

    /// The sign-out's removal waits far longer than a step (a lock freed meanwhile is taken):
    /// it doesn't go on with the lease still there while the lock is only busy.
    func testTheSignOutsRemovalWaitsUntilTheLockIsFree() async throws {
        XCTAssertTrue(lease("widget-1", wait: 1).acquire())
        let holder = try Holder(url)
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: clock.now)),
                                          store: RecordingSnapshotStore(), lease: lease("app-1", wait: 0.1))
        let started = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { holder.unlock() }
        await refresher.revokeLease()
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.45, "past the steps' own bound")
        XCTAssertNil(LeaseFile(url: url).storedOwner(), "the lease is gone")
    }

    /// A login while the lock is stuck: nothing is sent and it ends as busy (the user can try
    /// again), not a wait without end.
    func testALoginWhileTheLockIsStuckEndsAsBusy() async throws {
        let holder = try Holder(url)
        defer { holder.unlock() }
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: clock.now)),
                                          store: RecordingSnapshotStore(), lease: lease("app-1", wait: 0.1), leaseWait: 0,
                                          sleep: { _ in })
        do {
            _ = try await refresher.holdingLease { _ in XCTFail("the body never runs without the lease") }
            XCTFail("busy")
        } catch let failure as SchoolLoginFailure {
            XCTAssertEqual(failure, .busy)
        }
    }

    /// Many waits for a stuck lock at once (a foreground each, say): they suspend between tries,
    /// so other async work in the process still runs meanwhile.
    func testWaitsForAStuckLockLeaveSwiftConcurrencysPoolFree() async throws {
        let holder = try Holder(url)
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: clock.now)),
                                          store: RecordingSnapshotStore(), lease: lease("app-1", wait: 3))
        let stuck = lease("app-1", wait: 3)
        var waits = (0..<32).map { _ in Task.detached { await refresher.finishPendingClear(lockWait: 3) } }
        waits += (0..<32).map { _ in Task.detached { _ = await stuck.acquire(waitingAtMost: 3) } }
        try await Task.sleep(for: .milliseconds(100))

        let ran = expectation(description: "other async work ran while the lock was stuck")
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<32 { group.addTask { await Task.yield() } }
            }
            ran.fulfill()
        }
        await fulfillment(of: [ran], timeout: 1.5)

        holder.unlock()
        for wait in waits { await wait.value }
    }
}
