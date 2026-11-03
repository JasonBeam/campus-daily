import Foundation
#if canImport(os)
import os
#endif

/// The school read the refresher drives (`SchoolSession` in the app and the widget, fakes in
/// tests). `mayMint` is asked before every step that mints a card session, sends the saved
/// password or writes a credential back; false = stop there. Credential write-backs go
/// through `owning`, so every reader takes the lease check: there is no variant without it.
public protocol SchoolReader: Sendable {
    /// `numbers` may be called once, before the end, with a reading that is already worth
    /// storing (the balance and the meter while the card records are still on their way).
    func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool, owning: LeaseOwnership,
                 numbers: @Sendable (SchoolReading) async -> Void) async -> SchoolReading
    /// False only when the stored card session is known to be gone (signed out); a read that
    /// fails says nothing.
    func hasCardSession() async -> Bool
}

public extension SchoolReader {
    func hasCardSession() async -> Bool { true }
}

extension SchoolSession: SchoolReader {}

/// What one refresh produced.
public struct RefreshReport: Sendable, Equatable {
    public typealias Outcome = SchoolReading.Outcome
    public var outcome: Outcome
    public var snapshot: HomeSnapshot
    public var reexchanged: Bool
    public var snapshotSaved: Bool
    /// The other process held the lease the whole wait (it is reading, or it was suspended
    /// while holding it): nothing was read here. `snapshot` is the stored one, and the app
    /// shows it without an error.
    public var leaseBusy: Bool

    public init(outcome: Outcome, snapshot: HomeSnapshot, reexchanged: Bool, snapshotSaved: Bool, leaseBusy: Bool = false) {
        self.outcome = outcome; self.snapshot = snapshot; self.reexchanged = reexchanged; self.snapshotSaved = snapshotSaved
        self.leaseBusy = leaseBusy
    }
}

/// The only writer of the home snapshot the app and the widget read: each process has one
/// refresher, and they take turns through `RefreshLease`.
///
/// Reads the school data, reduces it into the stored snapshot and saves it. Refreshes are
/// single-flight within this process: a caller that arrives while one is running awaits that
/// same refresh and gets its report, so a pull-to-refresh during a foreground or background
/// read still ends with the fresh values (or the recorded failure). A failed read keeps the
/// last good values. Two exceptions to joining:
/// - a caller passing `includingChanges` after `noteChange()` (new login, meter chosen) waits
///   for the older read to end and then starts, or joins, a read that sees the change;
/// - when every caller waiting on a read is cancelled (an expiring background task), the read
///   is cancelled and writes nothing.
///
/// Across processes: a read runs only while this refresher holds the lease (waiting up to
/// `leaseWait` for the other process to finish first), renews it before minting, and gives it
/// back at the end. Writes are ordered: a reading older than the stored snapshot's `checkedAt`
/// is dropped, so a slow read in one process never overwrites a newer one from the other.
public actor SnapshotRefresher {
    let school: SchoolReader
    let store: SnapshotStoring
    /// Failures worth a look, by event name only (no values), e.g. the snapshot could not be saved.
    let diagnostic: @Sendable (String) -> Void
    /// Nil = this process is the only refresher (tests of the in-process rules).
    let lease: RefreshLease?
    let leaseWait: TimeInterval
    let sleep: @Sendable (TimeInterval) async -> Void
    /// How often the lease is renewed while a read runs.
    let renewInterval: TimeInterval

    private struct Run {
        let id: Int
        let task: Task<RefreshReport, Never>
        let inBackground: Bool
        let changes: Int
        var waiters = 0
        var cancelled = 0
    }

    private var current: Run?
    private var nextRunID = 0
    /// Bumped by `noteChange()`.
    private var changes = 0
    /// Bumped by `clear()` so a refresh that was running during sign-out does not write back.
    private var generation = 0
    /// Callers that joined a running refresh (for tests).
    private(set) var joinedCount = 0
    /// Waiters whose task was cancelled (for tests).
    private(set) var cancelledWaiters = 0

    /// Times come from the school reading (`checkedAt`, `readAt`), so the refresher needs no clock.
    public init(school: SchoolReader, store: SnapshotStoring, lease: RefreshLease? = nil, leaseWait: TimeInterval = 15,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                renewInterval: TimeInterval = RefreshLease.renewInterval,
                diagnostic: @escaping @Sendable (String) -> Void = SnapshotRefresher.osLog) {
        self.school = school; self.store = store; self.lease = lease; self.leaseWait = leaseWait; self.sleep = sleep
        self.renewInterval = renewInterval
        self.diagnostic = diagnostic
    }

    public static let osLog: @Sendable (String) -> Void = { event in
        #if canImport(os)
        Logger(subsystem: "com.beamjason.xiaorichang", category: "snapshot").error("\(event, privacy: .public)")
        #endif
    }

    /// The diagnostic line for a failed save: the storage status only.
    static func saveFailedEvent(_ error: Error) -> String {
        "snapshot.saveFailed" + ((error as? StorageError).map { " status=\($0.status)" } ?? "")
    }

    /// The stored snapshot, or `.empty`. Reading never waits for a running refresh.
    public nonisolated func latest() -> HomeSnapshot {
        ((try? store.loadSnapshot()) ?? nil) ?? .empty
    }

    /// Something the next read depends on changed (sign-in, meter choice). A refresh asked
    /// with `includingChanges` will not join a read that started before this.
    public func noteChange() { changes += 1 }

    /// Runs a refresh, or joins the one already running (see the type's rules).
    public func refresh(inBackground: Bool, includingChanges: Bool = false) async -> RefreshReport {
        while includingChanges, let run = current, run.changes != changes {
            _ = await wait(for: run.id, run.task)
        }
        if let run = current {
            joinedCount += 1
            return await wait(for: run.id, run.task)
        }
        nextRunID += 1
        let id = nextRunID
        let task = Task { () -> RefreshReport in
            let report = await self.run(inBackground: inBackground)
            self.finished(id)
            return report
        }
        current = Run(id: id, task: task, inBackground: inBackground, changes: changes)
        return await wait(for: id, task)
    }

    /// Signed out: the shared snapshot goes back to empty and the lease is removed (whoever
    /// holds it: the other process's read finds nobody signed in and writes nothing). A refresh
    /// still running here is dropped.
    public func clear() throws {
        generation += 1
        current = nil
        try? lease?.clear()
        try store.saveSnapshot(SchoolSnapshotReducer.reduce(latest(), .signedOut))
    }

    /// Sign-out and reset, before anything is deleted: the other process's read in progress
    /// loses the lease, so its next step (minting, the password login, saving the portal
    /// token, writing the session back) stops instead of writing a credential back. The file
    /// lock may be held by the other process's step for a moment: the wait happens on a
    /// background thread, never on the caller's (the app's main thread).
    public nonisolated func revokeLease() async {
        let lease = lease
        await Task.detached(priority: .userInitiated) { try? lease?.clear() }.value
    }

    private func wait(for id: Int, _ task: Task<RefreshReport, Never>) async -> RefreshReport {
        if current?.id == id { current?.waiters += 1 }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.waiterCancelled(id) }
        }
    }

    private func waiterCancelled(_ id: Int) {
        cancelledWaiters += 1
        guard var run = current, run.id == id else { return }
        run.cancelled += 1
        current = run
        if run.cancelled >= run.waiters {
            run.task.cancel()
            current = nil
        }
    }

    private func finished(_ id: Int) {
        if current?.id == id { current = nil }
    }

    /// A login from the app's form or Settings (password login, saving a password, the web
    /// sign-in), recharge and the hot-water hand-off under the lease, so none of them runs beside
    /// the other process's automatic login. Waits up to `leaseWait` for a read in either
    /// process; still held then, nothing is sent and `SchoolLoginFailure.busy` is thrown. The
    /// lease is kept alive while `body` runs and given back after it. Every credential `body`
    /// writes goes through `owning`: one locked step with the check that the lease is still
    /// ours, so there is no variant without it. The heartbeat stops quietly when a renewal fails
    /// (the app was suspended past the lease, and the other process may have taken it), while
    /// the body keeps running; its writes then find the lease lost and write nothing. Without a
    /// lease, or with one that has no file to lock (the app with no container for one, where no
    /// other process can take it either), `body` just runs with `.unchecked`.
    public nonisolated func holdingLease<T: Sendable>(_ body: @Sendable (_ owning: LeaseOwnership) async throws -> T) async throws -> T {
        guard let shared = lease, shared.isAvailable else { return try await body(.unchecked) }
        // Its own owner, one per call: neither the lease this process's refresh holds nor one
        // another login, recharge or hand-off here holds is "ours" to reuse, so a second one waits
        // for the first, and the first giving its lease back never releases the second's.
        let lease = shared.with(owner: shared.owner + "-login-" + UUID().uuidString)
        var waited: TimeInterval = 0
        while !lease.acquire() {
            guard waited < leaseWait else { throw SchoolLoginFailure.busy }
            try Task.checkCancellation()
            await sleep(1)
            waited += 1
        }
        let heartbeat = Self.keepAlive(lease, every: renewInterval)
        do {
            let value = try await body(LeaseOwnership(lease))
            heartbeat.cancel(); await heartbeat.value
            lease.release()
            return value
        } catch {
            heartbeat.cancel(); await heartbeat.value
            lease.release()
            throw error
        }
    }

    /// Takes the lease, waiting up to `leaseWait` while the other process holds it.
    private func acquireLease(_ lease: RefreshLease) async -> Bool {
        var waited: TimeInterval = 0
        while !lease.acquire() {
            guard lease.isAvailable, waited < leaseWait, !Task.isCancelled else { return false }
            await sleep(1)
            waited += 1
        }
        return true
    }

    private func run(inBackground: Bool) async -> RefreshReport {
        let started = generation
        // Its own owner, one per run: a run whose lease ran out (suspended, the other process
        // took and gave back the lease meanwhile) never passes as a later run of this process,
        // whose lease that is.
        let lease = self.lease.map { $0.with(owner: $0.owner + "-run-" + UUID().uuidString) }
        if let lease {
            guard await acquireLease(lease) else {
                // The other process is still reading; its result lands in the shared snapshot.
                diagnostic("snapshot.leaseBusy")
                return RefreshReport(outcome: .failed(.timedOut), snapshot: latest(), reexchanged: false, snapshotSaved: false,
                                     leaseBusy: true)
            }
        }
        // Kept alive for the whole read: a slow chain must not let the other process take over
        // halfway and mint or log in a second time.
        let heartbeat = lease.map { Self.keepAlive($0, every: renewInterval) }
        // The balance and the meter are stored as soon as they are in (a widget that runs out of
        // time while the card records load keeps them); the full reading is stored at the end.
        let reading = await school.refresh(inBackground: inBackground, mayMint: { lease?.renew() ?? true },
                                           owning: LeaseOwnership(lease),
                                           numbers: { [weak self] partial in
                                               _ = await self?.write(partial, started: started, lease: lease)
                                           })
        let report = await write(reading, started: started, lease: lease)
        // The heartbeat has stopped before the lease is given back: a renewal still running
        // would otherwise bring it back and hold the other process off for a whole lease.
        heartbeat?.cancel()
        await heartbeat?.value
        lease?.release()
        return report
    }

    /// Stores one reading under the same rules each time. Signed out meanwhile, or nobody
    /// wants this read any more: nothing is written. Lost the lease meanwhile (it ran out,
    /// whether or not another process took it, or a sign-out in the other process removed it),
    /// or the other process already wrote a newer reading: nothing is written either; a lease
    /// that ran out is not this read's failure to record.
    ///
    /// The lease check, the compare with the stored snapshot and the save are one locked step
    /// (`LeaseOwnership`): the other process can't take the lease, store a newer reading or
    /// revoke the lease for a sign-out in between. A sign-out right after the save is caught
    /// once more: nobody signed in any more and the lease gone, the snapshot is cleared again;
    /// still signed in with the lease only taken over, the save stays.
    private func write(_ reading: SchoolReading, started: Int, lease: RefreshLease?) async -> RefreshReport {
        guard started == generation, !Task.isCancelled else {
            let outcome: RefreshReport.Outcome = started == generation ? reading.outcome : .notSignedIn
            return RefreshReport(outcome: outcome, snapshot: latest(), reexchanged: reading.reexchanged, snapshotSaved: false)
        }
        enum Step { case older(HomeSnapshot), stored(HomeSnapshot, saved: Bool) }
        let store = store, diagnostic = diagnostic
        let step = (try? LeaseOwnership(lease).write { () -> Step in
            let stored = latest()
            guard !Self.isOlder(reading, than: stored) else { return .older(stored) }
            let snapshot = Self.apply(reading, to: stored)
            do { try store.saveSnapshot(snapshot) } catch {
                diagnostic(Self.saveFailedEvent(error))
                return .stored(snapshot, saved: false)
            }
            return .stored(snapshot, saved: true)
        }) ?? nil
        let snapshot: HomeSnapshot, saved: Bool
        switch step {
        case nil, .older?:
            let stored: HomeSnapshot
            if case .older(let s)? = step { stored = s } else { stored = latest() }
            return RefreshReport(outcome: reading.outcome, snapshot: stored, reexchanged: reading.reexchanged, snapshotSaved: false)
        case .stored(let s, let ok)?:
            snapshot = s; saved = ok
        }
        // Outside the lock, after the save: the other process may sign out now (its lease removal
        // first, then its items). The card session is read first and the lease checked after
        // that read, so a sign-out that lands while the session is read is still seen.
        if saved, let lease, !(await school.hasCardSession()), !lease.holds() {
            try? store.saveSnapshot(SchoolSnapshotReducer.reduce(latest(), .signedOut))
            return RefreshReport(outcome: .notSignedIn, snapshot: latest(), reexchanged: reading.reexchanged, snapshotSaved: false)
        }
        return RefreshReport(outcome: reading.outcome, snapshot: snapshot, reexchanged: reading.reexchanged, snapshotSaved: saved)
    }

    /// Renews `lease` every `interval` until cancelled or lost.
    private static func keepAlive(_ lease: RefreshLease, every interval: TimeInterval) -> Task<Void, Never> {
        Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(0.01, interval) * 1_000_000_000))
                guard !Task.isCancelled, lease.renew() else { return }
            }
        }
    }

    /// How far a reading in one process can trail one the other process stored: one read
    /// with the lease kept alive (a few minutes at most), with ample room. A clock set back by
    /// less than this holds updates off for at most this long.
    static let maxReadOverlap: TimeInterval = 30 * 60

    /// A reading checked before the stored snapshot was: the other process wrote a newer one.
    /// A stored check further ahead than any read could overlap means the clock moved back
    /// since then; that one is replaced, or the snapshot would never update again.
    public static func isOlder(_ reading: SchoolReading, than snapshot: HomeSnapshot) -> Bool {
        guard let stored = snapshot.checkedAt, reading.checkedAt < stored else { return false }
        return stored.timeIntervalSince(reading.checkedAt) <= maxReadOverlap
    }

    /// Pure: the snapshot after one school reading. A reading older than the snapshot changes
    /// nothing; nobody signed in leaves an empty snapshot empty (signed out in the other process).
    public static func apply(_ reading: SchoolReading, to snapshot: HomeSnapshot) -> HomeSnapshot {
        guard !isOlder(reading, than: snapshot) else { return snapshot }
        var s = snapshot
        switch reading.outcome {
        case .interrupted, .leaseLost:
            return s
        case .notSignedIn:
            guard s != .empty else { return s }
            s = SchoolSnapshotReducer.reduce(s, .sessionExpired(.sessionExpired(.ecykt), at: reading.checkedAt))
        case .needsLogin(let e):
            s = SchoolSnapshotReducer.reduce(s, .sessionExpired(e, at: reading.checkedAt))
        case .failed(let e):
            s = SchoolSnapshotReducer.reduce(s, .livenessFailed(e, at: reading.checkedAt))
        case .ok:
            s = SchoolSnapshotReducer.reduce(s, .livenessOK(at: reading.checkedAt))
            let at = reading.readAt ?? reading.checkedAt
            if let b = reading.balance { s = SchoolSnapshotReducer.reduce(s, .balance(b, at: at)) }
            if let a = reading.activity { s = SchoolSnapshotReducer.reduce(s, .activity(a, at: at)) }
            // No meter bound: the stored reading belonged to one that is gone.
            if reading.noMeter { s = SchoolSnapshotReducer.reduce(s, .meterUnbound) }
            if let m = reading.meter {
                s = SchoolSnapshotReducer.reduce(s, .meter(m, at: at))
                s = SchoolSnapshotReducer.reduce(s, .roomLabel(reading.roomLabel))
            }
        }
        return s
    }
}
