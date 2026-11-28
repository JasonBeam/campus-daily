//
//  SnapshotRefresher.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
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
    /// fails says nothing. Checked synchronously inside the commit lock before writing a snapshot.
    func hasCardSession() -> Bool
}

public extension SchoolReader {
    func hasCardSession() -> Bool { true }
}

extension SchoolSession: SchoolReader {}

/// What one refresh produced.
public struct RefreshReport: Sendable, Equatable {
    public typealias Outcome = SchoolReading.Outcome
    public var outcome: Outcome
    public var snapshot: HomeSnapshot
    public var snapshotSaved: Bool
    /// The other process held the lease the whole wait (it is reading, or it was suspended
    /// while holding it): nothing was read here. `snapshot` is the stored one, and the app
    /// shows it without an error.
    public var leaseBusy: Bool
    /// What this refresh says about the card balance (`SchoolReading.ownBalance`, never a stored
    /// value or one from the other process).
    public enum BalanceResult: Sendable, Equatable {
        /// The round's last write was skipped (judged older than the stored snapshot, the lease
        /// lost, signed out or cancelled meanwhile): it says nothing, the balance already held
        /// stays as it is.
        case discarded
        /// The round's result: its own read, or nil = unknown (this round really couldn't read
        /// it: never got the lease, the read failed or was interrupted, the card not this login's).
        case delivered(CardBalanceRead?)
    }
    public var balance: BalanceResult = .delivered(nil)
    /// The delivered read, if any (nil both for unknown and for a discarded round).
    public var ownBalance: CardBalanceRead? {
        if case .delivered(let read) = balance { return read }
        return nil
    }
    /// The round (run) that produced this report: rounds start in this order, and every caller
    /// that joined one gets the same number. 0 = not from a round.
    public var round: Int = 0
    /// The `tag` the caller that started the round passed (a caller that joined later gets the
    /// starter's, never its own).
    public var roundTag: Int = 0

    public init(outcome: Outcome, snapshot: HomeSnapshot, snapshotSaved: Bool, leaseBusy: Bool = false) {
        self.outcome = outcome; self.snapshot = snapshot; self.snapshotSaved = snapshotSaved
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
    /// Nil only in unit tests / sample mode (backed by `inMemoryLock`). Production always has a
    /// `RefreshLease` (which fails closed when its file is unavailable).
    public nonisolated let lease: RefreshLease?
    private nonisolated let inMemoryLock: InMemoryCommitLock?
    /// The commit lock for this refresher: `lease` in production (fails closed if its file is
    /// unavailable), or `inMemoryLock` in tests/samples. Never falls open.
    public nonisolated var commitLock: any SharedLock {
        if let lease { return lease }
        if let inMemoryLock { return inMemoryLock }
        return FailingSharedLock()
    }
    let leaseWait: TimeInterval
    let sleep: @Sendable (TimeInterval) async -> Void
    /// How often the lease is renewed while a read runs.
    let renewInterval: TimeInterval

    /// Thread-safe holder for the `SessionEpoch` tracked across partial + final writes of one run.
    private final class RunEpoch: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SessionEpoch?
        init(_ initial: SessionEpoch?) { value = initial }
        var current: SessionEpoch? {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    private struct Run {
        let id: Int
        let task: Task<RefreshReport, Never>
        let inBackground: Bool
        let changes: Int
        let tag: Int
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
    /// Times a caller asking for changes waited for a read that started before them (for tests).
    private(set) var changeWaitCount = 0
    /// Waiters whose task was cancelled (for tests).
    private(set) var cancelledWaiters = 0

    /// Times come from the school reading (`checkedAt`, `readAt`), so the refresher needs no clock.
    public init(school: SchoolReader, store: SnapshotStoring, lease: RefreshLease? = nil, leaseWait: TimeInterval = 15,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                renewInterval: TimeInterval = RefreshLease.renewInterval,
                diagnostic: @escaping @Sendable (String) -> Void = SnapshotRefresher.osLog,
                inMemoryLock: InMemoryCommitLock? = nil) {
        self.school = school; self.store = store; self.lease = lease; self.leaseWait = leaseWait; self.sleep = sleep
        self.renewInterval = renewInterval
        self.diagnostic = diagnostic
        self.inMemoryLock = lease == nil ? (inMemoryLock ?? InMemoryCommitLock()) : nil
    }

    public static let osLog: @Sendable (String) -> Void = { event in
        #if canImport(os)
        Logger(subsystem: "org.zaxh.xiaorichang", category: "snapshot").error("\(event, privacy: .public)")
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

    /// Runs a refresh, or joins the one already running (see the type's rules). `tag`: kept with
    /// a round this call starts and handed back in its report (`roundTag`).
    public func refresh(inBackground: Bool, includingChanges: Bool = false, tag: Int = 0) async -> RefreshReport {
        while includingChanges, let run = current, run.changes != changes {
            changeWaitCount += 1
            _ = await wait(for: run.id, run.task)
        }
        if let run = current {
            joinedCount += 1
            return await wait(for: run.id, run.task)
        }
        nextRunID += 1
        let id = nextRunID
        let task = Task { () -> RefreshReport in
            var report = await self.run(inBackground: inBackground)
            report.round = id
            report.roundTag = tag
            self.finished(id)
            return report
        }
        current = Run(id: id, task: task, inBackground: inBackground, changes: changes, tag: tag)
        return await wait(for: id, task)
    }

    /// Signed out or switched account: revokes the lease, invalidates any in-flight refresh in
    /// this process, wipes `shared.snapshot` to `.empty` inside the commit lock, and advances any
    /// pending-clear epoch (`.signedOutPendingClear` -> `.signedOut`, `.activePendingClear` -> `.active`).
    public func clear() async throws {
        await revokeLease()
        generation += 1
        current = nil
        let store = store
        if let lease {
            try await lease.locked(waitingAtMost: lease.lockWait) { try store.clearSnapshot() }
        } else if let inMemoryLock {
            try inMemoryLock.locked { try store.clearSnapshot() }
        } else {
            throw LeaseFile.Failure(step: "lock", code: ENOENT)
        }
    }

    /// Finishes any pending clear (`.activePendingClear`, `.signedOutPendingClear`, or legacy
    /// 0.11.5 `shared.snapshotStale`) inside the commit lock without using the network.
    /// Fails closed (does nothing) when the production lease has no lock file.
    public nonisolated func finishPendingClear() {
        let store = store
        if let lease {
            guard lease.isAvailable else { return }
            do { try lease.locked { try store.finishPendingClear() } } catch {
                pendingClearFailed(error)
            }
            return
        }
        if let inMemoryLock {
            do { try inMemoryLock.locked { try store.finishPendingClear() } } catch {
                pendingClearFailed(error)
            }
        }
    }

    /// `finishPendingClear()` for async callers (the app's launch and foreground, the widget
    /// before each timeline): the wait for the file's lock suspends, for at most `lockWait`
    /// seconds, and holds no thread meanwhile.
    public nonisolated func finishPendingClear(lockWait: TimeInterval) async {
        let store = store
        if let lease {
            guard lease.isAvailable else { return }
            do { try await lease.locked(waitingAtMost: lockWait) { try store.finishPendingClear() } } catch {
                pendingClearFailed(error)
            }
            return
        }
        if let inMemoryLock {
            do { try inMemoryLock.locked { try store.finishPendingClear() } } catch {
                pendingClearFailed(error)
            }
        }
    }

    private nonisolated func pendingClearFailed(_ error: Error) {
        diagnostic("snapshot.pendingClearFailed" + ((error as? StorageError).map { " status=\($0.status)" } ?? "")
                   + ((error as? LeaseFile.Failure)?.isLockTimeout == true ? " lock=timeout" : ""))
    }

    /// Sign-out and reset, before anything is deleted: the other process's read in progress
    /// loses the lease, so its next step (minting, the password login, saving the portal
    /// token, writing the session back) stops instead of writing a credential back. The file
    /// lock may be held by the other process's step for a moment: the wait suspends (no thread
    /// is held, the main thread included) for at most `RefreshLease.signOutLockWait`. A lock
    /// still held then is stuck; the sign-out goes on without the removal (logged), as after a
    /// removal that failed: every write-back also compares what is stored with what it read.
    public nonisolated func revokeLease() async {
        guard let lease else { return }
        do { try await lease.clear(waitingAtMost: RefreshLease.signOutLockWait) } catch {
            diagnostic("lease.clearFailed" + ((error as? LeaseFile.Failure)?.isLockTimeout == true ? " lock=timeout" : ""))
        }
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

    /// Runs a login or hot-water hand-off under the cross-process refresh lease.
    /// Fails closed (`SchoolLoginFailure.busy`) when the production lease has no lock file
    /// (`!shared.isAvailable`) or cannot be acquired — never falls back to `.unchecked`.
    public nonisolated func holdingLease<T: Sendable>(_ body: @Sendable (_ owning: LeaseOwnership) async throws -> T) async throws -> T {
        if let shared = lease {
            guard shared.isAvailable else {
                try Task.checkCancellation()
                throw SchoolLoginFailure.busy
            }
            // Its own owner, one per call: neither the lease this process's refresh holds nor one
            // another login or hand-off here holds is "ours" to reuse, so a second one waits
            // for the first, and the first giving its lease back never releases the second's.
            let lease = shared.with(owner: shared.owner + "-login-" + UUID().uuidString)
            guard await acquire(lease) else {
                try Task.checkCancellation()
                throw SchoolLoginFailure.busy
            }
            let heartbeat = Self.keepAlive(lease, every: renewInterval)
            do {
                let value = try await body(LeaseOwnership(lease))
                heartbeat.cancel(); await heartbeat.value
                await lease.release(waitingAtMost: lease.lockWait)
                return value
            } catch {
                heartbeat.cancel(); await heartbeat.value
                await lease.release(waitingAtMost: lease.lockWait)
                throw error
            }
        }
        if let inMemoryLock {
            return try await body(.inMemory(inMemoryLock))
        }
        throw SchoolLoginFailure.busy
    }

    /// The shortest lock wait one try to take the lease gets, even with `leaseWait` (nearly) used up.
    static let minimumLockWait: TimeInterval = 0.25

    /// Takes the lease, trying again every second (`sleep`) while another owner holds it, until
    /// `leaseWait` has gone by. The time is the wall clock's, the lock waits included, so the
    /// widget's whole wait stays within its few seconds; each try's lock wait is cut to what is
    /// left (at least `minimumLockWait`). The time `sleep` was asked for counts as well, so tests
    /// with an instant `sleep` still end after `leaseWait` sleeps. A file lock that stays held for
    /// one whole lock wait (`LeaseFile.defaultLockWait`) is stuck, the other process suspended
    /// inside a step: it ends the wait at once. No file to lock, or cancelled: false at once.
    nonisolated func acquire(_ lease: RefreshLease) async -> Bool {
        guard lease.isAvailable else { return false }
        let started = DispatchTime.now().uptimeNanoseconds
        var slept: TimeInterval = 0
        func left() -> TimeInterval {
            let elapsed = TimeInterval(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            return leaseWait - max(elapsed, slept)
        }
        while true {
            let wait = min(lease.lockWait, max(Self.minimumLockWait, left()))
            switch await lease.acquire(waitingAtMost: wait) {
            case .taken:
                return true
            case .lockTimeout:
                diagnostic("snapshot.leaseLockTimeout")
                return false
            case .held, .unusable:
                let remaining = left()
                guard remaining > 0, !Task.isCancelled else { return false }
                let pause = min(1, remaining)
                await sleep(pause)
                slept += pause
            }
        }
    }

    private func run(inBackground: Bool) async -> RefreshReport {
        let started = generation
        // Its own owner, one per run: a run whose lease ran out (suspended, the other process
        // took and gave back the lease meanwhile) never passes as a later run of this process,
        // whose lease that is.
        let lease = self.lease.map { $0.with(owner: $0.owner + "-run-" + UUID().uuidString) }
        if let lease {
            guard await acquire(lease) else {
                // The other process is still reading; its result lands in the shared snapshot.
                diagnostic("snapshot.leaseBusy")
                return RefreshReport(outcome: .failed(.timedOut), snapshot: latest(), snapshotSaved: false,
                                     leaseBusy: true)
            }
        }
        // Kept alive for the whole read: a slow chain must not let the other process take over
        // halfway and mint or log in a second time.
        let heartbeat = lease.map { Self.keepAlive($0, every: renewInterval) }
        let ownership: LeaseOwnership
        if let lease {
            ownership = LeaseOwnership(lease)
        } else if let inMemoryLock {
            ownership = .inMemory(inMemoryLock)
        } else {
            ownership = .unavailable
        }
        let store = store, school = school
        let startEpoch: SessionEpoch?
        do {
            guard let prepared = try await ownership.write({ () throws -> SessionEpoch? in
                try store.prepareRefreshEpoch(hasCardSession: school.hasCardSession())
            }) else {
                heartbeat?.cancel(); await heartbeat?.value
                if let lease { await lease.release(waitingAtMost: lease.lockWait) }
                return RefreshReport(outcome: .leaseLost, snapshot: latest(), snapshotSaved: false)
            }
            startEpoch = prepared
        } catch {
            heartbeat?.cancel(); await heartbeat?.value
            if let lease { await lease.release(waitingAtMost: lease.lockWait) }
            return RefreshReport(outcome: .interrupted, snapshot: latest(), snapshotSaved: false)
        }
        if let startEpoch, !startEpoch.allowsRefreshCommit {
            heartbeat?.cancel(); await heartbeat?.value
            if let lease { await lease.release(waitingAtMost: lease.lockWait) }
            return RefreshReport(outcome: .notSignedIn, snapshot: .empty, snapshotSaved: false)
        }
        let runEpoch = RunEpoch(startEpoch)
        // The balance and the meter are stored as soon as they are in (a widget that runs out of
        // time while the card records load keeps them); the full reading is stored at the end.
        let reading = await school.refresh(inBackground: inBackground,
                                           mayMint: {
                                               guard let lease else { return true }
                                               return await lease.renew(waitingAtMost: lease.lockWait)
                                           },
                                           owning: ownership,
                                           numbers: { [weak self] partial in
                                               _ = await self?.write(partial, started: started, runEpoch: runEpoch,
                                                                     ownership: ownership, lease: lease)
                                           })
        let (written, stored) = await write(reading, started: started, runEpoch: runEpoch,
                                            ownership: ownership, lease: lease)
        var report = written
        // Only a read this round actually stored as the newest one (whether or not the local save
        // then failed) is delivered; a failed current round delivers unknown. One whose last write
        // was skipped (older, lease lost, signed out, cancelled) is discarded: it must not clear a
        // balance already held either.
        if !stored || started != generation {
            report.balance = .discarded
        } else {
            report.balance = .delivered(report.outcome == .ok ? reading.ownBalance : nil)
        }
        // The heartbeat has stopped before the lease is given back: a renewal still running
        // would otherwise bring it back and hold the other process off for a whole lease.
        heartbeat?.cancel()
        await heartbeat?.value
        if let lease { await lease.release(waitingAtMost: lease.lockWait) }
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
    /// `stored`: this reading went into the snapshot as the newest one (its save attempted under
    /// the lease, and not lost to a sign-out right after); false when it was skipped.
    @discardableResult
    private func write(_ reading: SchoolReading, started: Int, runEpoch: RunEpoch,
                       ownership: LeaseOwnership, lease: RefreshLease?) async -> (report: RefreshReport, stored: Bool) {
        guard started == generation, !Task.isCancelled else {
            let outcome: RefreshReport.Outcome = started == generation ? reading.outcome : .notSignedIn
            return (RefreshReport(outcome: outcome, snapshot: latest(), snapshotSaved: false), false)
        }
        if reading.outcome == .interrupted || reading.outcome == .leaseLost {
            return (RefreshReport(outcome: reading.outcome, snapshot: latest(), snapshotSaved: false),
                    reading.outcome == .interrupted)
        }
        enum Step {
            case older(HomeSnapshot)
            case signedOut(HomeSnapshot)
            case epochRejected(HomeSnapshot)
            case stored(HomeSnapshot, saved: Bool, committedEpoch: SessionEpoch?)
        }
        let store = store, school = school, diagnostic = diagnostic, expected = runEpoch.current
        let step = (try? await ownership.write { () -> Step in
            guard school.hasCardSession() else {
                return .signedOut(latest())
            }
            let currentEpoch: SessionEpoch?
            do { currentEpoch = try store.sessionEpoch() } catch {
                return .epochRejected(latest())
            }
            if let expected {
                guard let currentEpoch, currentEpoch.id == expected.id, currentEpoch.allowsRefreshCommit else {
                    return .epochRejected(latest())
                }
            } else if currentEpoch != nil {
                return .epochRejected(latest())
            }
            let stored = latest()
            guard !Self.isOlder(reading, than: stored) else { return .older(stored) }
            let snapshot = Self.apply(reading, to: stored)
            do {
                guard let result = try store.commitSnapshot(snapshot, expectedEpoch: expected) else {
                    return .epochRejected(latest())
                }
                return .stored(result.snapshot, saved: true, committedEpoch: result.epoch)
            } catch {
                diagnostic(Self.saveFailedEvent(error))
                return .stored(snapshot, saved: false, committedEpoch: nil)
            }
        }) ?? nil
        let snapshot: HomeSnapshot, saved: Bool
        switch step {
        case .signedOut(let stored)?:
            return (RefreshReport(outcome: .notSignedIn, snapshot: stored, snapshotSaved: false), false)
        case nil, .older?, .epochRejected?:
            let stored: HomeSnapshot
            if case .older(let s)? = step { stored = s }
            else if case .epochRejected(let s)? = step { stored = s }
            else { stored = latest() }
            return (RefreshReport(outcome: reading.outcome, snapshot: stored, snapshotSaved: false), false)
        case .stored(let s, let ok, let committedEpoch)?:
            snapshot = s; saved = ok
            if ok { runEpoch.current = committedEpoch }
        }
        return (RefreshReport(outcome: reading.outcome, snapshot: snapshot, snapshotSaved: saved), true)
    }

    /// Renews `lease` every `interval` until cancelled or lost.
    private static func keepAlive(_ lease: RefreshLease, every interval: TimeInterval) -> Task<Void, Never> {
        Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(0.01, interval) * 1_000_000_000))
                guard !Task.isCancelled, await lease.renew(waitingAtMost: lease.lockWait) else { return }
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
            guard !s.isEmpty else { return s }
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
