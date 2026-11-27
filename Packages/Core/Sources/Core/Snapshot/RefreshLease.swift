//
//  RefreshLease.swift
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

/// The cross-process lock around a school refresh. The app and the widget are two processes
/// sharing one stored card session; only the holder of this lease refreshes (and so mints or
/// rotates the session). The lease is one small file `{owner, expiresAt}` in the App Group
/// container both processes can open. Every step (take, renew, check, give back, clear) is one
/// read-compare-write done while holding an exclusive `flock` on that file, so two processes can
/// never both find the same lease free, and a holder whose lease ran out can never write over
/// the next one's. The lock is held only for that step, never across an `await`: iOS ends a
/// suspended process that still holds a file lock in a shared container.
///
/// A step waits at most `LeaseFile.defaultLockWait` for the lock (a lock held longer is stuck:
/// the other process suspended inside a step) and then counts as a lock it could not get: no
/// lease, nothing written. Async callers (every step of the app's and the widget's refresh,
/// login and write-backs) wait by suspending between `LOCK_NB` tries (`acquire(waitingAtMost:)`,
/// `withOwnership(waitingAtMost:retaking:_:)` and the rest): no thread is held while the lock
/// is taken elsewhere, neither one of Swift concurrency's pool nor the main thread. The
/// synchronous steps (`acquire()`, `locked(_:)`, ...) park their thread for up to that bound;
/// only tests and `AppReset`'s synchronous clean-up still call them.
///
/// A holder that dies leaves its lease to expire after `duration`; the next process takes it.
/// Without the shared container (a build signed without the App Group) the app keeps the lease
/// in its own container (`appFile`), so its own reads and logins still take turns; the widget's
/// `file` is nil and its lease can never be taken, so it leaves every read to the app.
public struct RefreshLease: Sendable {
    struct Record: Codable, Equatable {
        var owner: String
        var expiresAt: Date
    }

    /// The lease file in the shared container, or nil when this build has no App Group (none it
    /// is entitled to, under the Info.plist name or its own bundle id: `AppIdentity.usableAppGroup`).
    public static func sharedFile(appGroup: String? = AppIdentity.usableAppGroup) -> LeaseFile? {
        appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            .map { LeaseFile(url: $0.appendingPathComponent("refresh.lease")) }
    }

    /// The app's lease file: the shared one, or, in a build without the App Group, one in the
    /// app's own container (`ownContainer`, Application Support; created when missing). The widget
    /// can't open that one, so it never reads (`sharedFile` is nil there too), while the app's own
    /// reads, logins and hand-off still take turns: `flock` on separate descriptors
    /// excludes within one process as well. That file is created here and excluded from backup
    /// (a restore must not bring a lease back). nil only when neither can be used.
    public static func appFile(appGroup: String? = AppIdentity.usableAppGroup,
                               ownContainer: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first) -> LeaseFile? {
        if let shared = sharedFile(appGroup: appGroup) { return shared }
        guard let ownContainer,
              (try? FileManager.default.createDirectory(at: ownContainer, withIntermediateDirectories: true)) != nil
        else { return nil }
        var url = ownContainer.appendingPathComponent("refresh.lease")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return LeaseFile(url: url)
    }

    let file: LeaseFile?
    /// Random per refresher (process): `app-<uuid>` / `widget-<uuid>`. Nothing personal.
    public let owner: String
    let now: @Sendable () -> Date
    public let duration: TimeInterval

    /// Longer than the slowest refresh chain: liveness, portal exchange, one password login and
    /// the exchange after it, each up to 20 s on a slow network, plus the reads (60–180 s).
    public static let defaultDuration: TimeInterval = 180
    /// The holder pushes the expiry forward this often while its read runs.
    public static let renewInterval: TimeInterval = 20

    public init(file: LeaseFile?, owner: String, duration: TimeInterval = RefreshLease.defaultDuration,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.file = file; self.owner = owner; self.duration = duration; self.now = now
    }

    /// The same file under another owner (a login from the app's form beside its own refresh).
    func with(owner: String) -> RefreshLease { RefreshLease(file: file, owner: owner, duration: duration, now: now) }

    /// A new owner id for one process: the role plus a random UUID.
    public static func owner(_ role: String) -> String { role + "-" + UUID().uuidString }

    /// False when there is no shared file to lock: nobody can take the lease.
    public var isAvailable: Bool { file != nil }

    /// How long a step waits for the file's lock (`LeaseFile.lockWait`).
    public var lockWait: TimeInterval { file?.lockWait ?? LeaseFile.defaultLockWait }

    /// How long a sign-out's removal of the lease waits for the file's lock: far longer than
    /// any step holds it, so only a stuck lock (the other process suspended inside a step) runs
    /// it out. The sign-out then goes on without the removal (`SnapshotRefresher.revokeLease`).
    public static let signOutLockWait: TimeInterval = 10

    /// Takes the lease when nobody holds it, or when the holder's lease has run out (an
    /// owner whose own lease ran out takes it afresh like anyone else). False while another
    /// owner holds a live lease, or when the file can't be opened, read or written (a locked
    /// phone before the first unlock): no lease, no refresh.
    public func acquire() -> Bool {
        update { current in
            if let holder = current, holder.owner != owner, !isStale(holder) { return (current, false) }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), true)
        } ?? false
    }

    /// Still ours and not run out: push the expiry forward. False = lost (it ran out, another
    /// process took it, or a sign-out removed it): stop before minting, logging in or writing a
    /// credential. Nothing is written then.
    public func renew() -> Bool {
        update { current in
            guard let holder = current, holder.owner == owner, holder.expiresAt > now() else { return (current, false) }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), true)
        } ?? false
    }

    /// One locked step for a write-back: while this owner still holds a live lease, its expiry
    /// is pushed forward and `body` runs inside the same lock, so the other process can neither
    /// take the lease nor clear it between the check and what `body` compares and writes. nil =
    /// not ours any more (ran out, taken, removed by a sign-out) or no usable file: `body` did not
    /// run. Once `body` ran its result is returned even when the pushed-forward expiry could not
    /// be stored afterwards: the write happened, and the lease stays ours until its old expiry
    /// (the next renewal finds out). `body` is synchronous and short (a Keychain or snapshot
    /// write); no `await` can run inside the lock. What `body` throws is rethrown.
    public func withOwnership<T>(_ body: () throws -> T) throws -> T? {
        var ran: Result<T, Error>?
        _ = update { current -> (Record?, Void) in
            guard let holder = current, holder.owner == owner, holder.expiresAt > now() else { return (current, ()) }
            ran = Result { try body() }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), ())
        }
        return try ran?.get()
    }

    /// `withOwnership` for the one write that may follow a lease which only ran out: this owner
    /// is still the stored one (nobody took the lease since, and no sign-out removed it), so
    /// nobody else wrote a credential meanwhile: every credential writer needs the lease and a
    /// sign-out removes it first. The lease is taken again (expiry pushed forward) and `body`
    /// runs, in the same locked step. nil = another owner, no lease, or no usable file.
    func withOwnershipRetaking<T>(_ body: () throws -> T) throws -> T? {
        var ran: Result<T, Error>?
        _ = update { current -> (Record?, Void) in
            guard let holder = current, holder.owner == owner else { return (current, ()) }
            ran = Result { try body() }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), ())
        }
        return try ran?.get()
    }

    /// `body` inside the file's lock, whoever holds the lease; the lease itself is left as it is.
    /// For a write that needs no lease of its own but must not land between another owner's
    /// compare and write (保存密码 off). Fails closed when `file` is nil or can't be opened,
    /// locked, or read (protected before the first unlock): throws that error and `body` does
    /// not run. What `body` throws is rethrown; once `body` ran, its result stands even if the
    /// file could not be written after.
    public func locked<T>(_ body: () throws -> T) throws -> T {
        guard let file else { throw LeaseFile.Failure(step: "lock", code: ENOENT) }
        var ran: Result<T, Error>?
        do {
            _ = try file.update { current -> (RefreshLease.Record?, Void) in
                ran = Result { try body() }
                return (current, ())
            }
        } catch {
            guard ran != nil else { throw error }
        }
        guard let ran else { throw LeaseFile.Failure(step: "lock", code: EIO) }
        return try ran.get()
    }

    /// `acquire()` without waiting for the lock: false while another step holds it. Tests use it
    /// as the other process trying at one exact moment.
    func tryAcquire() -> Bool {
        update(waiting: false) { current in
            if let holder = current, holder.owner != owner, !isStale(holder) { return (current, false) }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), true)
        } ?? false
    }

    /// `clear()` without waiting for the lock: false while another step holds it (tests: the
    /// other process's sign-out trying at one exact moment).
    func tryClear() -> Bool {
        guard let file else { return false }
        return (try? file.update(waiting: false) { _ in (nil, true) }) ?? false
    }

    /// `body` inside the file's lock, only when the lease is not this owner's any more (taken
    /// over, or removed by a sign-out). nil = still ours, or no usable file: `body` did not run.
    func afterLosing<T>(_ body: () -> T) -> T? {
        update { current in (current, current?.owner == owner ? nil : body()) } ?? nil
    }

    /// Still ours (not taken over, not removed by a sign-out in the other process).
    public func holds() -> Bool {
        update { current in (current, current?.owner == owner) } ?? false
    }

    /// The lease goes, whoever holds it, waiting for the lock however long another step holds
    /// it and parking the calling thread meanwhile (tests). The app's sign-out and reset use
    /// `clear(waitingAtMost:)` (`SnapshotRefresher.revokeLease`), whose wait suspends.
    public func clear() throws {
        guard let file else { throw LeaseFile.Failure(step: "lock", code: ENOENT) }
        _ = try file.update(wait: .unbounded) { _ in (nil, ()) }
    }

    /// Gives the lease back if it is still ours.
    public func release() {
        _ = update { current in current?.owner == owner ? (nil, ()) : (current, ()) }
    }

    /// Run out, or set further ahead than any holder would (a clock moved back): either way
    /// nobody is using it.
    func isStale(_ record: Record) -> Bool {
        let t = now()
        return record.expiresAt <= t || record.expiresAt > t.addingTimeInterval(duration * 2)
    }

    /// The stored lease (for tests and diagnostics).
    func read() throws -> Record? {
        guard let file else { return nil }
        return try file.update { current in (current, current) }
    }

    /// One locked read-compare-write; nil when the file can't be used.
    private func update<T>(waiting: Bool = true, _ body: (Record?) -> (Record?, T)) -> T? {
        guard let file else { return nil }
        return try? file.update(waiting: waiting, body)
    }
}

// MARK: - Steps for async callers

extension RefreshLease {
    /// One locked step that waits by suspending (`LeaseFile.update(waitingAtMost:)`).
    enum Step<T> {
        case done(T)
        /// The lock stayed held by another step for the whole wait (stuck, most likely).
        case lockTimeout
        /// No file, one that can't be opened, read or written, or the task was cancelled.
        case unusable
    }

    private func step<T>(isolation: isolated (any Actor)? = #isolation, waitingAtMost wait: TimeInterval,
                         untilCancelled: Bool = true, _ body: (Record?) -> (Record?, T)) async -> Step<T> {
        guard let file else { return .unusable }
        do {
            return .done(try await file.update(waitingAtMost: wait, untilCancelled: untilCancelled, body))
        } catch let failure as LeaseFile.Failure where failure.isLockTimeout {
            return .lockTimeout
        } catch {
            return .unusable
        }
    }

    /// What `acquire(waitingAtMost:)` found.
    public enum Acquisition: Sendable, Equatable {
        case taken
        /// Another owner holds a live lease.
        case held
        /// The file's lock stayed held for the whole wait: another step is stuck inside it.
        case lockTimeout
        /// No usable file (before the first unlock), or the task was cancelled.
        case unusable
    }

    /// `acquire()` for async callers: waits up to `wait` for the file's lock by suspending.
    public func acquire(waitingAtMost wait: TimeInterval) async -> Acquisition {
        let result: Step<Bool> = await step(waitingAtMost: wait) { current in
            if let holder = current, holder.owner != owner, !isStale(holder) { return (current, false) }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), true)
        }
        switch result {
        case .done(let took): return took ? .taken : .held
        case .lockTimeout: return .lockTimeout
        case .unusable: return .unusable
        }
    }

    /// `renew()` for async callers: false also when the lock can't be had within `wait`.
    public func renew(waitingAtMost wait: TimeInterval) async -> Bool {
        let result: Step<Bool> = await step(waitingAtMost: wait) { current in
            guard let holder = current, holder.owner == owner, holder.expiresAt > now() else { return (current, false) }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), true)
        }
        if case .done(let renewed) = result { return renewed }
        return false
    }

    /// `release()` for async callers. A lock that stays held leaves the lease to run out. A
    /// cancelled read (the widget past its deadline) still gives its lease back.
    public func release(waitingAtMost wait: TimeInterval) async {
        let _: Step<Void> = await step(waitingAtMost: wait, untilCancelled: false) { current in
            current?.owner == owner ? (nil, ()) : (current, ())
        }
    }

    /// `clear()` for async callers (sign-out, reset), waiting up to `wait` by suspending.
    /// Throws `LeaseFile.Failure` when the lease could not be removed (`isLockTimeout`: the
    /// lock stayed held).
    public func clear(waitingAtMost wait: TimeInterval) async throws {
        guard let file else { throw LeaseFile.Failure(step: "lock", code: ENOENT) }
        _ = try await file.update(waitingAtMost: wait, untilCancelled: false) { _ in (nil, ()) }
    }

    /// What a write under the lease came to (`withOwnership(waitingAtMost:retaking:_:)`).
    public enum Owned<T> {
        case ran(T)
        /// Not ours any more (ran out, taken, removed by a sign-out), no usable file, or the
        /// task was cancelled: `body` did not run.
        case lost
        /// The file's lock stayed held for the whole wait: nothing is known about the lease,
        /// and `body` did not run.
        case lockTimeout
    }

    /// `withOwnership` (or, `retaking`, `withOwnershipRetaking`) for async callers: the same
    /// one locked step, waiting up to `wait` for the lock by suspending. `body` runs in the
    /// caller's isolation, inside the lock; what it throws is rethrown.
    func withOwnership<T>(isolation: isolated (any Actor)? = #isolation, waitingAtMost wait: TimeInterval, retaking: Bool,
                          _ body: () throws -> T) async throws -> Owned<T> {
        var ran: Result<T, Error>?
        let result: Step<Void> = await step(waitingAtMost: wait) { current -> (Record?, Void) in
            guard let holder = current, holder.owner == owner, retaking || holder.expiresAt > now() else { return (current, ()) }
            ran = Result { try body() }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), ())
        }
        if let ran { return .ran(try ran.get()) }
        if case .lockTimeout = result { return .lockTimeout }
        return .lost
    }

    /// `afterLosing` for async callers; nil also when the lock can't be had within `wait`.
    func afterLosing<T>(isolation: isolated (any Actor)? = #isolation, waitingAtMost wait: TimeInterval,
                        _ body: () -> T) async -> T? {
        let result: Step<T?> = await step(waitingAtMost: wait) { current in
            (current, current?.owner == owner ? nil : body())
        }
        if case .done(let value) = result { return value }
        return nil
    }

    /// `locked` for async callers: waits up to `lockWait` for the lock by suspending.
    public func lockedWhenFree<T>(isolation: isolated (any Actor)?, _ body: () throws -> T) async throws -> T {
        try await locked(waitingAtMost: lockWait, body)
    }

    /// `locked` for async callers, waiting up to `wait` for the lock by suspending.
    func locked<T>(isolation: isolated (any Actor)? = #isolation, waitingAtMost wait: TimeInterval,
                   _ body: () throws -> T) async throws -> T {
        guard let file else { throw LeaseFile.Failure(step: "lock", code: ENOENT) }
        var ran: Result<T, Error>?
        do {
            _ = try await file.update(waitingAtMost: wait) { current -> (RefreshLease.Record?, Void) in
                ran = Result { try body() }
                return (current, ())
            }
        } catch {
            guard ran != nil else { throw error }
        }
        guard let ran else { throw LeaseFile.Failure(step: "lock", code: EIO) }
        return try ran.get()
    }

    /// `locked` without waiting at all: throws at once while another step holds the lock
    /// (the main thread: `ThemeStore.select`).
    public func lockedIfFree<T>(_ body: () throws -> T) throws -> T {
        guard let file else { throw LeaseFile.Failure(step: "lock", code: ENOENT) }
        var ran: Result<T, Error>?
        do {
            _ = try file.update(wait: .no) { current -> (RefreshLease.Record?, Void) in
                ran = Result { try body() }
                return (current, ())
            }
        } catch {
            guard ran != nil else { throw error }
        }
        guard let ran else { throw LeaseFile.Failure(step: "lock", code: EIO) }
        return try ran.get()
    }
}

/// The lease file's lock guards the other shared state too (the App Group's preferences):
/// `locked` runs a step whoever holds the lease.
extension RefreshLease: SharedLock {}
