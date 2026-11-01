import XCTest
@testable import Core
import CoreTestSupport

/// Snapshot store that records every write.
final class RecordingSnapshotStore: SnapshotStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: HomeSnapshot?
    private(set) var writes: [HomeSnapshot] = []
    init(_ initial: HomeSnapshot? = nil) { stored = initial }
    func loadSnapshot() throws -> HomeSnapshot? { lock.withLock { stored } }
    func saveSnapshot(_ snapshot: HomeSnapshot) throws { lock.withLock { stored = snapshot; writes.append(snapshot) } }
    var writeCount: Int { lock.withLock { writes.count } }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func append(_ e: String) { lock.withLock { events.append(e) } }
    var all: [String] { lock.withLock { events } }
}

/// School reader that answers a scripted reading and counts calls.
final class ScriptedSchoolReader: PlainSchoolReader, @unchecked Sendable {
    private let lock = NSLock()
    private var reading: SchoolReading
    private(set) var calls = 0
    init(_ reading: SchoolReading) { self.reading = reading }
    func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool) async -> SchoolReading {
        lock.withLock { calls += 1; return reading }
    }
    var callCount: Int { lock.withLock { calls } }
}

final class SnapshotRefresherTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 2_000)
    let meter = Meter(comAddress: "000000000991", name: "99栋991")

    func goodSnapshot() -> HomeSnapshot {
        var s = SchoolSnapshotReducer.reduce(.empty, .balance(.success(Money(fen: 790)), at: t0))
        s = SchoolSnapshotReducer.reduce(s, .meter(.success(meter), at: t0))
        return s
    }

    func testRefreshReducesTheReadingAndWritesOnce() async {
        let store = RecordingSnapshotStore()
        let reader = ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 500)),
                                                        meter: .success(meter), roomLabel: "99栋 991", readAt: t1))
        let refresher = SnapshotRefresher(school: reader, store: store)
        let report = await refresher.refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertTrue(report.snapshotSaved)
        XCTAssertEqual(store.writeCount, 1)
        XCTAssertEqual(refresher.latest(), report.snapshot)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 500))
        XCTAssertEqual(report.snapshot.card.fetchedAt, t1)
        XCTAssertEqual(report.snapshot.power.value, meter)
        XCTAssertEqual(report.snapshot.roomLabel, "99栋 991")
        XCTAssertEqual(report.snapshot.checkedAt, t1)
    }

    func testFailedReadKeepsLastValuesAndRecordsTheFailure() async {
        let store = RecordingSnapshotStore(goodSnapshot())
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .failed(.offline), checkedAt: t1)),
                                          store: store)
        let report = await refresher.refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .failed(.offline))
        let saved = refresher.latest()
        XCTAssertEqual(saved, report.snapshot)
        XCTAssertEqual(saved.card.value, Money(fen: 790))
        XCTAssertEqual(saved.card.fetchedAt, t0)
        XCTAssertEqual(saved.card.error, .offline)
        XCTAssertEqual(saved.card.errorAt, t1)
        XCTAssertEqual(saved.power.value, meter)
        XCTAssertEqual(saved.power.fetchedAt, t0)
        XCTAssertEqual(saved.power.error, .offline)
        XCTAssertFalse(saved.needsLogin)
        XCTAssertEqual(store.writeCount, 1, "the failure is written so the app and widget can show it")
    }

    func testOneSourceFailingKeepsItsOldValueWhileTheOtherUpdates() async {
        let store = RecordingSnapshotStore(goodSnapshot())
        let newer = Meter(comAddress: "000000000991", name: "99栋991", leftMoney: Money(fen: 1200))
        let reading = SchoolReading(outcome: .ok, checkedAt: t1, balance: .failure(.timedOut), meter: .success(newer),
                                    roomLabel: "99栋 991", readAt: t1)
        let report = await SnapshotRefresher(school: ScriptedSchoolReader(reading), store: store).refresh(inBackground: false)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 790))
        XCTAssertEqual(report.snapshot.card.fetchedAt, t0)
        XCTAssertEqual(report.snapshot.card.error, .timedOut)
        XCTAssertEqual(report.snapshot.card.errorAt, t1)
        XCTAssertEqual(report.snapshot.power.value, newer)
        XCTAssertEqual(report.snapshot.power.fetchedAt, t1)
        XCTAssertNil(report.snapshot.power.error)
    }

    func testNeedsLoginKeepsValuesAndFlagsTheSnapshot() async {
        let store = RecordingSnapshotStore(goodSnapshot())
        let reading = SchoolReading(outcome: .needsLogin(.sessionExpired(.ecykt)), checkedAt: t1)
        let report = await SnapshotRefresher(school: ScriptedSchoolReader(reading), store: store).refresh(inBackground: true)
        XCTAssertTrue(report.snapshot.needsLogin)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 790))
        XCTAssertEqual(report.snapshot.card.error, .sessionExpired(.ecykt))
        XCTAssertEqual(store.writeCount, 1)
    }

    func testClearWritesEmpty() async throws {
        let store = RecordingSnapshotStore(goodSnapshot())
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1)), store: store)
        try await refresher.clear()
        XCTAssertEqual(refresher.latest(), .empty)
        XCTAssertEqual(store.writeCount, 1)
    }

    func testStoreWriteFailureIsReported() async {
        let mem = InMemorySecureStore()
        mem.failWrites(to: .sharedSnapshot)
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(SchoolReading(outcome: .failed(.offline), checkedAt: t1)),
                                          store: SharedSnapshotStore(store: mem))
        let report = await refresher.refresh(inBackground: false)
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertEqual(report.snapshot.card.error, .offline)
    }

    /// A failed save leaves one diagnostic line with the storage status and no values.
    func testStoreWriteFailureIsLogged() async {
        let mem = InMemorySecureStore()
        mem.failWrites(to: .sharedSnapshot)
        let events = EventLog()
        let reading = SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 99123)), readAt: t1)
        let refresher = SnapshotRefresher(school: ScriptedSchoolReader(reading), store: SharedSnapshotStore(store: mem),
                                          diagnostic: { events.append($0) })
        let report = await refresher.refresh(inBackground: false)
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertEqual(events.all, ["snapshot.saveFailed status=-1"])
        XCTAssertFalse(events.all.joined().contains("991"))
        // A successful save logs nothing.
        mem.failWrites(to: .sharedSnapshot, false)
        _ = await refresher.refresh(inBackground: false)
        XCTAssertEqual(events.all.count, 1)
    }
}

/// School reader that holds every call until the test releases it.
final class GatedSchoolReader: PlainSchoolReader, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<SchoolReading, Never>] = []
    private var calls = 0
    private var backgroundFlags: [Bool] = []
    func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool) async -> SchoolReading {
        await withCheckedContinuation { c in lock.withLock { calls += 1; backgroundFlags.append(inBackground); waiting.append(c) } }
    }
    var callCount: Int { lock.withLock { calls } }
    /// `inBackground` of every read, in order.
    var inBackground: [Bool] { lock.withLock { backgroundFlags } }
    var waitingCount: Int { lock.withLock { waiting.count } }
    func release(_ reading: SchoolReading) {
        let all = lock.withLock { let w = waiting; waiting = []; return w }
        for c in all { c.resume(returning: reading) }
    }
}

/// Polls `condition` until it holds (2 s cap).
func eventually(_ condition: @Sendable () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<400 {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("condition never held", file: file, line: line)
}

final class SnapshotRefresherSingleFlightTests: XCTestCase {
    let t1 = Date(timeIntervalSince1970: 2_000)

    /// A pull-to-refresh while another refresh runs waits for it and gets its result.
    func testConcurrentRefreshesShareOneRead() async {
        let reader = GatedSchoolReader()
        let store = RecordingSnapshotStore()
        let refresher = SnapshotRefresher(school: reader, store: store)
        async let first = refresher.refresh(inBackground: true)
        await eventually { reader.waitingCount == 1 }
        async let second = refresher.refresh(inBackground: false)
        await eventually { await refresher.joinedCount == 1 }
        reader.release(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 321)), readAt: t1))
        let (a, b) = await (first, second)
        XCTAssertEqual(reader.callCount, 1, "one network read for both callers")
        XCTAssertEqual(a, b)
        XCTAssertEqual(b.snapshot.card.value, Money(fen: 321))
        XCTAssertEqual(b.snapshot.card.fetchedAt, t1)
        XCTAssertEqual(store.writeCount, 1)
    }

    /// A joined caller also gets the failure, never a silent no-op.
    func testJoinedCallerGetsTheFailure() async {
        let reader = GatedSchoolReader()
        let refresher = SnapshotRefresher(school: reader, store: RecordingSnapshotStore())
        async let first = refresher.refresh(inBackground: false)
        await eventually { reader.waitingCount == 1 }
        async let second = refresher.refresh(inBackground: false)
        await eventually { await refresher.joinedCount == 1 }
        reader.release(SchoolReading(outcome: .failed(.timedOut), checkedAt: t1))
        let (a, b) = await (first, second)
        XCTAssertEqual(a.outcome, .failed(.timedOut))
        XCTAssertEqual(b.outcome, .failed(.timedOut))
        XCTAssertEqual(b.snapshot.card.errorAt, t1)
    }

    func testRefreshAfterTheRunningOneEndsReadsAgain() async {
        let reader = ScriptedSchoolReader(SchoolReading(outcome: .ok, checkedAt: t1))
        let refresher = SnapshotRefresher(school: reader, store: RecordingSnapshotStore())
        _ = await refresher.refresh(inBackground: false)
        _ = await refresher.refresh(inBackground: false)
        XCTAssertEqual(reader.callCount, 2)
        let joined = await refresher.joinedCount
        XCTAssertEqual(joined, 0)
    }

    /// Sign-out while a read is running: the late result is not written back over the empty snapshot.
    func testClearDuringRefreshDropsTheLateResult() async throws {
        let reader = GatedSchoolReader()
        let store = RecordingSnapshotStore()
        let refresher = SnapshotRefresher(school: reader, store: store)
        async let running = refresher.refresh(inBackground: false)
        await eventually { reader.waitingCount == 1 }
        try await refresher.clear()
        reader.release(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 1)), readAt: t1))
        let report = await running
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertEqual(refresher.latest(), .empty)
        XCTAssertEqual(store.writeCount, 1)
    }

    /// The background read runs the same ladder as a foreground one (the portal token is
    /// readable after the first unlock), so a foreground caller that joined it takes its answer,
    /// `needsLogin` included, without a second read.
    func testForegroundJoiningBackgroundNeedsLoginTakesItsAnswer() async {
        let reader = GatedSchoolReader()
        let refresher = SnapshotRefresher(school: reader, store: RecordingSnapshotStore())
        async let background = refresher.refresh(inBackground: true)
        await eventually { reader.waitingCount == 1 }
        async let foreground = refresher.refresh(inBackground: false)
        await eventually { await refresher.joinedCount == 1 }
        reader.release(SchoolReading(outcome: .needsLogin(.sessionExpired(.ecykt)), checkedAt: t1))
        let (b, f) = await (background, foreground)
        XCTAssertEqual(reader.inBackground, [true])
        XCTAssertEqual(b, f)
        XCTAssertEqual(f.outcome, .needsLogin(.sessionExpired(.ecykt)))
    }

    /// A background caller that joins a foreground read keeps that read's answer.
    func testBackgroundJoiningNeverStartsASecondRead() async {
        let reader = GatedSchoolReader()
        let refresher = SnapshotRefresher(school: reader, store: RecordingSnapshotStore())
        async let foreground = refresher.refresh(inBackground: false)
        await eventually { reader.waitingCount == 1 }
        async let background = refresher.refresh(inBackground: true)
        await eventually { await refresher.joinedCount == 1 }
        reader.release(SchoolReading(outcome: .needsLogin(.sessionExpired(.ecykt)), checkedAt: t1))
        let (f, b) = await (foreground, background)
        XCTAssertEqual(f, b)
        XCTAssertEqual(reader.callCount, 1)
    }

    /// A meter was chosen while a read was running: a caller asking for changes does not get
    /// the old read's result; it waits and reads again, and two such callers share that read.
    func testChangeDuringReadIsReadAgainNotJoined() async {
        let reader = GatedSchoolReader()
        let store = RecordingSnapshotStore()
        let refresher = SnapshotRefresher(school: reader, store: store)
        async let old = refresher.refresh(inBackground: false)
        await eventually { reader.waitingCount == 1 }
        await refresher.noteChange()
        async let a = refresher.refresh(inBackground: false, includingChanges: true)
        async let b = refresher.refresh(inBackground: false, includingChanges: true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(reader.callCount, 1, "nothing starts while the old read runs")
        reader.release(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 1)), readAt: t1))
        await eventually { reader.callCount == 2 && reader.waitingCount == 1 }
        reader.release(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 2)), readAt: t1))
        let (o, x, y) = await (old, a, b)
        XCTAssertEqual(o.snapshot.card.value, Money(fen: 1))
        XCTAssertEqual(x.snapshot.card.value, Money(fen: 2))
        XCTAssertEqual(y.snapshot.card.value, Money(fen: 2))
        XCTAssertEqual(reader.callCount, 2, "the two callers after the change share one read")
        XCTAssertEqual(store.writeCount, 2)
    }

    /// Without a change, asking for changes still joins.
    func testIncludingChangesJoinsWhenNothingChanged() async {
        let reader = GatedSchoolReader()
        let refresher = SnapshotRefresher(school: reader, store: RecordingSnapshotStore())
        async let first = refresher.refresh(inBackground: false)
        await eventually { reader.waitingCount == 1 }
        async let second = refresher.refresh(inBackground: false, includingChanges: true)
        await eventually { await refresher.joinedCount == 1 }
        reader.release(SchoolReading(outcome: .ok, checkedAt: t1))
        _ = await (first, second)
        XCTAssertEqual(reader.callCount, 1)
    }

    /// The background task expired: its only caller is cancelled, so the read is cancelled
    /// down to the network and nothing is written.
    func testCancellingEveryWaiterCancelsTheRead() async {
        let reader = CancellableSchoolReader()
        let store = RecordingSnapshotStore()
        let refresher = SnapshotRefresher(school: reader, store: store)
        let caller = Task { await refresher.refresh(inBackground: true) }
        await eventually { reader.startedCount == 1 }
        caller.cancel()
        _ = await caller.value
        XCTAssertEqual(reader.cancelledCount, 1, "the read saw the cancellation")
        XCTAssertEqual(store.writeCount, 0)
    }

    /// The first caller goes away; the caller that joined still gets the read and it is written.
    func testFirstCallerCancelledDoesNotAffectTheJoinedCaller() async {
        let reader = GatedSchoolReader()
        let store = RecordingSnapshotStore()
        let refresher = SnapshotRefresher(school: reader, store: store)
        let first = Task { await refresher.refresh(inBackground: true) }
        await eventually { reader.waitingCount == 1 }
        async let joined = refresher.refresh(inBackground: true)
        await eventually { await refresher.joinedCount == 1 }
        first.cancel()
        await eventually { await refresher.cancelledWaiters == 1 }
        reader.release(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(fen: 7)), readAt: t1))
        let report = await joined
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertTrue(report.snapshotSaved)
        XCTAssertEqual(store.writeCount, 1)
        XCTAssertEqual(refresher.latest().card.value, Money(fen: 7))
        _ = await first.value
    }
}

/// School reader that waits until cancelled (or released) and records the cancellation.
final class CancellableSchoolReader: PlainSchoolReader, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<SchoolReading, Never>?
    private var started = 0, cancelled = 0, cancelledEarly = false
    var startedCount: Int { lock.withLock { started } }
    var cancelledCount: Int { lock.withLock { cancelled } }
    func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool) async -> SchoolReading {
        let offline = SchoolReading(outcome: .failed(.offline), checkedAt: Date(timeIntervalSince1970: 0))
        return await withTaskCancellationHandler {
            await withCheckedContinuation { c in
                let resumeNow = lock.withLock { () -> Bool in
                    started += 1
                    if cancelledEarly { return true }
                    waiting = c
                    return false
                }
                if resumeNow { c.resume(returning: offline) }
            }
        } onCancel: {
            let c = lock.withLock { () -> CheckedContinuation<SchoolReading, Never>? in
                cancelled += 1; cancelledEarly = true
                let w = waiting; waiting = nil; return w
            }
            c?.resume(returning: offline)
        }
    }
}

/// A read that lost the lease is not a failure: the stored numbers stay, with no error.
final class LeaseLostReadingTests: XCTestCase {
    func testALostLeaseChangesNothingInTheSnapshot() {
        var s = HomeSnapshot()
        s.card.succeed(Money(fen: 8650), at: Date(timeIntervalSince1970: 1_000))
        let reading = SchoolReading(outcome: .leaseLost, checkedAt: Date(timeIntervalSince1970: 2_000))
        let after = SnapshotRefresher.apply(reading, to: s)
        XCTAssertEqual(after, s)
        XCTAssertNil(after.card.error)
        XCTAssertFalse(after.needsLogin)
    }
}
