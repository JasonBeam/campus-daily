import XCTest
@testable import Core
import CoreTestSupport

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_793_300_000)
    var now: Date { lock.withLock { current } }
    func advance(_ s: TimeInterval) { lock.withLock { current = current.addingTimeInterval(s) } }
    var function: @Sendable () -> Date { { [self] in self.now } }
}

final class RefreshLeaseTests: XCTestCase {
    let store = InMemorySecureStore()
    let clock = TestClock()
    func lease(_ owner: String) -> RefreshLease { RefreshLease(file: store.leaseFile, owner: owner, now: clock.function) }

    func testOneHolderAtATime() {
        let app = lease("app-1"), widget = lease("widget-1")
        XCTAssertTrue(app.acquire())
        XCTAssertFalse(widget.acquire())
        XCTAssertTrue(app.holds())
        XCTAssertFalse(widget.holds())
        app.release()
        XCTAssertTrue(widget.acquire())
        XCTAssertFalse(app.acquire())
    }

    /// The write-back step runs only for the live holder, renews it, and keeps the lock while it runs.
    func testAWriteUnderOwnershipRunsOnlyForTheLiveHolder() throws {
        let app = lease("app-1"), widget = lease("widget-1")
        XCTAssertNil(try app.withOwnership { XCTFail("not taken yet") }, "nobody holds it")
        XCTAssertTrue(app.acquire())
        let value = try app.withOwnership { () -> Int in
            XCTAssertFalse(widget.tryAcquire(), "locked while the write runs")
            return 7
        }
        XCTAssertEqual(value, 7)
        clock.advance(RefreshLease.defaultDuration - 1)
        XCTAssertFalse(widget.acquire(), "the step renewed the lease")
        clock.advance(RefreshLease.defaultDuration)
        XCTAssertNil(try app.withOwnership { XCTFail("ran out") })
        XCTAssertTrue(widget.acquire())
        XCTAssertNil(try app.withOwnership { XCTFail("taken") })
        XCTAssertThrowsError(try widget.withOwnership { throw CocoaError(.fileWriteUnknown) }, "what the write throws is rethrown")
        XCTAssertTrue(widget.holds())
    }

    /// Sign-out from the app while the widget is inside a lease step: the wait for the file
    /// lock happens off the main thread, so the screen keeps responding until it is free.
    @MainActor func testRevokingTheLeaseWaitsForTheLockOffTheMainThread() async throws {
        final class Flag: @unchecked Sendable {
            private let lock = NSLock(); private var value = false
            func set() { lock.withLock { value = true } }
            var isSet: Bool { lock.withLock { value } }
        }
        let entered = expectation(description: "the widget holds the lock"), release = DispatchSemaphore(value: 0), released = Flag()
        let free = { released.set(); release.signal() }
        let busy = LeaseFile(url: store.leaseFile.url, insideLock: { entered.fulfill(); release.wait() })
        let widget = RefreshLease(file: busy, owner: "widget-1", now: clock.function)
        let stepDone = expectation(description: "the widget's step ended")
        DispatchQueue.global().async { _ = widget.acquire(); stepDone.fulfill() }
        await fulfillment(of: [entered], timeout: 30)
        // Only frees a main thread that the old blocking wait would hold: never reached when
        // the wait is off the main thread, which is checked first.
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { free() }

        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: clock.now)),
                                          store: RecordingSnapshotStore(),
                                          lease: RefreshLease(file: store.leaseFile, owner: "app-1", now: clock.function))
        let started = expectation(description: "revoking started")
        let revoked = Task { @MainActor in started.fulfill(); await refresher.revokeLease() }
        await fulfillment(of: [started], timeout: 30)
        XCTAssertFalse(released.isSet, "the main thread ran on while the lock was held")
        free()
        await revoked.value
        await fulfillment(of: [stepDone], timeout: 30)
        XCTAssertNil(store.leaseFile.storedOwner(), "the lease is gone once the lock was free")
    }

    /// The write ran, but the pushed-forward expiry could not be stored: that is still a write
    /// that happened (the caller must not treat it as skipped), and the lease stays ours until
    /// its old expiry.
    func testAWriteThatRanCountsEvenWhenTheRenewalCannotBeStored() throws {
        let app = lease("app-1")
        XCTAssertTrue(app.acquire())
        clock.advance(10)
        let failing = RefreshLease(file: LeaseFile(url: store.leaseFile.url, insideLock: nil, failsWrites: true),
                                   owner: "app-1", now: clock.function)
        var runs = 0
        let value = try failing.withOwnership { () -> Int in runs += 1; return 7 }
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(value, 7, "reported as run")
        XCTAssertThrowsError(try failing.withOwnership { () -> Int in throw CocoaError(.fileWriteUnknown) },
                             "what the write throws is still rethrown")
        XCTAssertTrue(app.holds(), "still ours")
        clock.advance(RefreshLease.defaultDuration - 10)
        XCTAssertFalse(app.renew(), "not renewed: it runs out at the old expiry")
    }

    /// The widget past its deadline (its task cancelled) writes nothing back under the lease
    /// and does not even take the file lock: a process about to be suspended must not hold it.
    func testAWriteUnderOwnershipIsSkippedOnceCancelled() async throws {
        final class Count: @unchecked Sendable {
            private let lock = NSLock(); private var value = 0
            func add() { lock.withLock { value += 1 } }
            var now: Int { lock.withLock { value } }
        }
        let locks = Count()
        let file = LeaseFile(url: store.leaseFile.url, insideLock: { locks.add() })
        let widget = RefreshLease(file: file, owner: "widget-1", now: clock.function)
        XCTAssertTrue(widget.acquire())
        let before = locks.now
        let wrote = try await Task { () throws -> Int? in
            withUnsafeCurrentTask { $0?.cancel() }
            return try LeaseOwnership(widget).write { 1 }
        }.value
        XCTAssertNil(wrote, "nothing written once cancelled")
        XCTAssertEqual(locks.now, before, "the lock was not taken")
        XCTAssertEqual(try LeaseOwnership(widget).write { 2 }, 2, "not cancelled, it writes")
    }

    /// A holder that died leaves its lease to run out; then the next process takes it.
    func testStaleLeaseExpires() {
        let app = lease("app-1"), widget = lease("widget-1")
        XCTAssertTrue(app.acquire())
        clock.advance(RefreshLease.defaultDuration - 1)
        XCTAssertFalse(widget.acquire())
        clock.advance(1)
        XCTAssertTrue(widget.acquire())
        XCTAssertFalse(app.holds())
        XCTAssertFalse(app.renew(), "the old holder finds out before it mints")
    }

    func testRenewPushesTheExpiry() {
        let app = lease("app-1"), widget = lease("widget-1")
        XCTAssertTrue(app.acquire())
        clock.advance(50)
        XCTAssertTrue(app.renew())
        clock.advance(50)
        XCTAssertFalse(widget.acquire())
        XCTAssertTrue(app.holds())
    }

    func testReleaseNeverRemovesSomeoneElsesLease() {
        let app = lease("app-1"), widget = lease("widget-1")
        XCTAssertTrue(widget.acquire())
        app.release()
        XCTAssertTrue(widget.holds())
    }

    /// An unreadable record or one set far ahead (clock moved back) can't block refreshes.
    func testGarbageOrFarFutureLeaseIsStale() throws {
        try Data("garbage".utf8).write(to: store.leaseFile.url)
        XCTAssertTrue(lease("app-1").acquire())
        let far = try JSONEncoder().encode(RefreshLease.Record(owner: "widget-9", expiresAt: clock.now.addingTimeInterval(3600)))
        try far.write(to: store.leaseFile.url)
        XCTAssertTrue(lease("app-1").acquire())
    }

    /// The file can't be opened (protected before the first unlock): no lease, no refresh.
    func testUnusableFileGivesNoLease() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-dir-\(UUID().uuidString)/lease")
        XCTAssertFalse(RefreshLease(file: LeaseFile(url: missing), owner: "app-1", now: clock.function).acquire())
    }

    /// Built without the App Group: nobody can take the lease, and the refresher does not wait for it.
    func testNoSharedFileGivesNoLease() {
        let lease = RefreshLease(file: nil, owner: "widget-1")
        XCTAssertFalse(lease.isAvailable)
        XCTAssertFalse(lease.acquire())
        XCTAssertFalse(lease.renew())
    }

    func testOwnerIdsAreRandomPerProcess() {
        let a = RefreshLease.owner("widget"), b = RefreshLease.owner("widget")
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.hasPrefix("widget-"))
    }
}

/// Two refreshers (app and widget) over one store.
final class TwoRefresherTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 2_000)
    let t2 = Date(timeIntervalSince1970: 3_000)

    func refresher(_ reader: SchoolReader, _ mem: InMemorySecureStore, owner: String, wait: TimeInterval = 400) -> SnapshotRefresher {
        SnapshotRefresher(school: reader, store: SharedSnapshotStore(store: mem),
                          lease: RefreshLease(file: mem.leaseFile, owner: owner, now: { Date(timeIntervalSince1970: 0) }),
                          leaseWait: wait, sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) })
    }

    /// The second process waits for the first one's read to end, then reads itself.
    func testTheOtherProcessWaitsForTheLease() async {
        let mem = InMemorySecureStore()
        let first = GatedSchoolReader()
        let second = ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t2, balance: .success(Money(fen: 2)), readAt: t2))
        let app = refresher(first, mem, owner: "app-1"), widget = refresher(second, mem, owner: "widget-1")
        async let a = app.refresh(inBackground: false)
        await eventually { first.waitingCount == 1 }
        async let w = widget.refresh(inBackground: true)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(second.callCount, 0)
        first.release(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 1)), readAt: t1))
        let (ra, rw) = await (a, w)
        XCTAssertTrue(ra.snapshotSaved)
        XCTAssertTrue(rw.snapshotSaved)
        XCTAssertEqual(second.callCount, 1)
        XCTAssertEqual(widget.latest().card.value, Money(fen: 2))
        XCTAssertNil(mem.leaseFile.storedOwner())
    }

    /// Still held after the wait: no read, nothing written, the stored snapshot is returned.
    func testBusyLeaseReturnsTheStoredSnapshot() async throws {
        let mem = InMemorySecureStore()
        XCTAssertTrue(RefreshLease(file: mem.leaseFile, owner: "app-1", now: { Date(timeIntervalSince1970: 0) }).acquire())
        let reader = ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1))
        let report = await refresher(reader, mem, owner: "widget-1", wait: 2).refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .failed(.timedOut))
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertEqual(reader.callCount, 0)
        XCTAssertNil(try mem.read(.sharedSnapshot))
    }

    /// The app tells "the widget held the lease" apart from a failed read, so it shows the
    /// stored numbers without an error. A read that ran reports `leaseBusy` false.
    func testBusyLeaseIsMarkedSoTheAppShowsNoError() async throws {
        let mem = InMemorySecureStore()
        let stored = SchoolSnapshotReducer.reduce(.empty, .balance(.success(Money(fen: 700)), at: t1))
        try SharedSnapshotStore(store: mem).saveSnapshot(stored)
        let widget = RefreshLease(file: mem.leaseFile, owner: "widget-1", now: { Date(timeIntervalSince1970: 0) })
        XCTAssertTrue(widget.acquire())
        let reader = ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t2))
        let busy = await refresher(reader, mem, owner: "app-1", wait: 2).refresh(inBackground: false)
        XCTAssertTrue(busy.leaseBusy)
        XCTAssertEqual(busy.snapshot, stored)
        widget.release()
        let ran = await refresher(reader, mem, owner: "app-1", wait: 2).refresh(inBackground: false)
        XCTAssertFalse(ran.leaseBusy)
        XCTAssertTrue(ran.snapshotSaved)
    }

    /// A slow read that finishes after a newer one was stored never overwrites it.
    func testOlderReadingNeverOverwritesANewerSnapshot() async throws {
        let mem = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: mem)
        var newer = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: t2))
        newer = SchoolSnapshotReducer.reduce(newer, .balance(.success(Money(fen: 900)), at: t2))
        try snapshots.saveSnapshot(newer)
        let old = ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 100)), readAt: t1))
        let report = await refresher(old, mem, owner: "app-1").refresh(inBackground: false)
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertEqual(report.snapshot, newer)
        XCTAssertEqual(try snapshots.loadSnapshot(), newer)
    }

    func testApplyIgnoresAnOlderReadingAndKeepsEmptyWhenSignedOut() {
        var s = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: t1))
        s = SchoolSnapshotReducer.reduce(s, .balance(.success(Money(fen: 5)), at: t1))
        XCTAssertEqual(SnapshotRefresher.apply(SchoolReading(outcome: .failed(.offline), checkedAt: t0), to: s), s)
        XCTAssertNotEqual(SnapshotRefresher.apply(SchoolReading(outcome: .failed(.offline), checkedAt: t1), to: s), s, "same time is not older")
        XCTAssertEqual(SnapshotRefresher.apply(SchoolReading(outcome: .notSignedIn, checkedAt: t2), to: .empty), .empty)
    }

    /// The clock was set back after a check was stored: the stored time is far in the future of
    /// every new reading. Those readings are written, not dropped as older.
    func testAReadingAfterTheClockMovedBackStillUpdates() async throws {
        let ahead = Date(timeIntervalSince1970: 1_793_330_000)
        let mem = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: mem)
        var stored = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: ahead))
        stored = SchoolSnapshotReducer.reduce(stored, .balance(.success(Money(fen: 900)), at: ahead))
        try snapshots.saveSnapshot(stored)
        let now = ahead.addingTimeInterval(-24 * 3600)
        let reading = SchoolReading(outcome: .ok, checkedAt: now, balance: .success(Money(fen: 100)), readAt: now)
        XCTAssertFalse(SnapshotRefresher.isOlder(reading, than: stored))
        let report = await refresher(ScriptedSchoolReader(reading), mem, owner: "app-1").refresh(inBackground: false)
        XCTAssertTrue(report.snapshotSaved)
        XCTAssertEqual(try snapshots.loadSnapshot()?.checkedAt, now)
        XCTAssertEqual(try snapshots.loadSnapshot()?.card.value, Money(fen: 100))
        // A reading only a little behind is still the other process's older one.
        let slow = SchoolReading(outcome: .ok, checkedAt: ahead.addingTimeInterval(-120))
        XCTAssertTrue(SnapshotRefresher.isOlder(slow, than: stored))
    }
}

/// Another process trying at the moment the lease file is locked: it runs on its own thread
/// with its own file descriptor, so it has to wait for the lock as the other process would.
final class Rival: @unchecked Sendable {
    // @unchecked: `result` is written before `done` is signalled and read after waiting on it.
    private let done = DispatchSemaphore(value: 0)
    private var result = false
    init(_ body: @escaping @Sendable () -> Bool) {
        Thread { [self] in result = body(); done.signal() }.start()
    }
    func join() -> Bool { done.wait(); return result }
}

/// Runs a step once, the first time the hooked lease file is locked and read.
final class OnceInsideLock: @unchecked Sendable {
    // @unchecked: `step` guarded by `lock`.
    private let lock = NSLock()
    private var step: (() -> Void)?
    func set(_ body: @escaping () -> Void) { lock.withLock { step = body } }
    func fire() { lock.withLock { () -> (() -> Void)? in defer { step = nil }; return step }?() }
}

/// The other process steps in exactly between a lease step's read and its write.
final class LeaseRenewRaceTests: XCTestCase {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lease-\(UUID().uuidString)")
    let clock = TestClock()
    let hook = OnceInsideLock()
    /// The process under test: its file runs `hook` inside the lock.
    func hooked(_ owner: String) -> RefreshLease {
        let hook = hook
        return RefreshLease(file: LeaseFile(url: url, insideLock: { hook.fire() }), owner: owner, now: clock.function)
    }
    /// The other process: the same file, no hook.
    func other(_ owner: String) -> RefreshLease { RefreshLease(file: LeaseFile(url: url), owner: owner, now: clock.function) }

    /// Whether another descriptor is kept out of the file right now.
    func lockIsHeld() -> Bool {
        let fd = open(url.path, O_RDWR)
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) != 0 else { flock(fd, LOCK_UN); return false }
        return errno == EWOULDBLOCK
    }

    /// Two processes find the same run-out lease at the same moment: only one comes away holding it.
    func testTwoTakersOfAnExpiredLeaseOnlyOneWins() throws {
        XCTAssertTrue(other("app-0").acquire())
        clock.advance(RefreshLease.defaultDuration + 1)
        let app = hooked("app-1"), widget = other("widget-1")
        var rival: Rival?
        var held = false
        hook.set { held = self.lockIsHeld(); rival = Rival { widget.acquire() } }
        let appTook = app.acquire()
        let widgetTook = try XCTUnwrap(rival).join()
        XCTAssertTrue(held, "the read, the check and the write happen under the lock")
        XCTAssertTrue(appTook != widgetTook, "exactly one holder (app \(appTook), widget \(widgetTook))")
        XCTAssertEqual(app.holds(), appTook)
        XCTAssertEqual(widget.holds(), widgetTook)
    }

    /// The holder's lease runs out between its renewal's read and its write, and the other
    /// process tries to take it then: the late renewal must not overwrite the new holder.
    func testStaleOwnerRenewingDoesNotOverwriteTheNewOwner() throws {
        let app = hooked("app-1"), widget = other("widget-1")
        XCTAssertTrue(app.acquire())
        clock.advance(RefreshLease.defaultDuration - 1)
        var rival: Rival?
        hook.set {
            self.clock.advance(2)
            rival = Rival { widget.acquire() }
        }
        let renewed = app.renew()
        let widgetTook = try XCTUnwrap(rival).join()
        XCTAssertTrue(widgetTook)
        XCTAssertFalse(renewed, "the old holder finds out it lost the lease")
        XCTAssertTrue(widget.holds(), "the new holder keeps it")
        XCTAssertFalse(app.holds())
    }

    /// A sign-out in the other process clears the lease while a renewal runs: the renewal goes
    /// first or second, never in between, and the lease is gone at the end.
    func testRenewDoesNotBringBackALeaseRevokedMeanwhile() throws {
        let widget = hooked("widget-1"), app = other("app-1")
        XCTAssertTrue(widget.acquire())
        var rival: Rival?
        hook.set { rival = Rival { (try? app.clear()) != nil } }
        _ = widget.renew()
        XCTAssertTrue(try XCTUnwrap(rival).join())
        XCTAssertNil(LeaseFile(url: url).storedOwner())
        XCTAssertFalse(widget.renew(), "the holder finds out before it mints")
        XCTAssertTrue(app.acquire(), "the other process is not held off")
    }

    /// The holder gives the lease back while its own heartbeat is renewing it.
    func testRenewDoesNotBringBackALeaseReleasedMeanwhile() throws {
        let app = hooked("app-1"), widget = other("widget-1")
        XCTAssertTrue(app.acquire())
        let giver = other("app-1")
        var rival: Rival?
        hook.set { rival = Rival { giver.release(); return true } }
        _ = app.renew()
        _ = try XCTUnwrap(rival).join()
        XCTAssertNil(LeaseFile(url: url).storedOwner())
        XCTAssertTrue(widget.acquire())
    }
}

final class InMemoryReplaceTests: XCTestCase {
    func testInMemoryReplaceNeverAdds() throws {
        let memory = InMemorySecureStore()
        XCTAssertFalse(try memory.replace(Data("a".utf8), for: .sharedRefreshLease))
        XCTAssertNil(try memory.read(.sharedRefreshLease))
        try memory.write(Data("a".utf8), for: .sharedRefreshLease)
        XCTAssertTrue(try memory.replace(Data("b".utf8), for: .sharedRefreshLease))
        XCTAssertEqual(try memory.read(.sharedRefreshLease), Data("b".utf8))
    }
}
