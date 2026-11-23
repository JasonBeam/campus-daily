//
//  LeaseFile.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The lease's file: `update` reads the record, lets the caller decide, and writes the
/// decision back, all under one exclusive `flock`. An empty file is "no lease"; an unreadable
/// one counts as long expired, so it can't block refreshes forever.
public struct LeaseFile: Sendable {
    public let url: URL
    /// Runs inside the lock right after the record was read (tests use it to let the other
    /// "process" try at exactly that moment).
    let insideLock: (@Sendable () -> Void)?
    /// Every changed record fails to be written (tests: a full or broken container).
    let failsWrites: Bool

    /// How long a step waits for the lock (`Wait.bounded`).
    let lockWait: TimeInterval

    public init(url: URL) { self.init(url: url, insideLock: nil) }

    init(url: URL, insideLock: (@Sendable () -> Void)?, failsWrites: Bool = false,
         lockWait: TimeInterval = LeaseFile.defaultLockWait) {
        self.url = url; self.insideLock = insideLock; self.failsWrites = failsWrites; self.lockWait = lockWait
    }

    struct Failure: Error {
        let step: String; let code: Int32
        /// The lock was held by another step for the whole wait (`Wait.no` at once, a bounded
        /// or suspending wait at its end).
        var isLockTimeout: Bool { step == "lock" && code == EWOULDBLOCK }
    }

    /// The stored owner, run out or not (nil = no lease). Read by the tests only.
    func storedOwner() -> String? { ((try? update { ($0, $0?.owner) }) ?? nil) }

    /// How a step waits for the file's lock.
    enum Wait: Sendable {
        /// Not at all: fails at once while another step holds it.
        case no
        /// Up to `LeaseFile.lockWait`, trying again every few milliseconds, then fails as a lock
        /// it could not get. Every step but the sign-out's removal.
        case bounded
        /// Until it is free (the synchronous `RefreshLease.clear`, tests only: the app's
        /// sign-out removes the lease with a bounded wait that suspends, `clear(waiting:)`).
        case unbounded
    }

    /// The longest a step waits for the lock before it gives up (`Wait.bounded`). A step holds
    /// it for a Keychain or snapshot write at most; one held longer is stuck (the other process
    /// suspended inside a step), and waiting on would park the thread for good.
    public static let defaultLockWait: TimeInterval = 2

    func update<T>(waiting: Bool = true, _ body: (RefreshLease.Record?) -> (RefreshLease.Record?, T)) throws -> T {
        try update(wait: waiting ? .bounded : .no, body)
    }

    /// How often a suspended wait tries the lock again.
    static let pollInterval: UInt64 = 10_000_000

    /// `update` for async callers: tries the lock without waiting (`LOCK_NB`) and, while
    /// another step holds it, suspends for `pollInterval` and tries again, for at most `wait`
    /// seconds. No thread waits meanwhile: not the caller's actor, not one of Swift
    /// concurrency's pool, not the main thread. `body` runs in the caller's isolation, inside
    /// the lock, without an `await`. Still held after `wait`: `Failure.isLockTimeout`. A
    /// cancelled task stops waiting (`CancellationError`); `body` has not run then. Unless
    /// `untilCancelled` is false: a step that must still run in a cancelled task (giving the
    /// lease back, a sign-out's removal) waits its whole bound all the same.
    func update<T>(isolation: isolated (any Actor)? = #isolation, waitingAtMost wait: TimeInterval, untilCancelled: Bool = true,
                   _ body: (RefreshLease.Record?) -> (RefreshLease.Record?, T)) async throws -> T {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, wait) * 1_000_000_000)
        while true {
            do {
                return try update(wait: .no, body)
            } catch let failure as Failure where failure.isLockTimeout {
                guard DispatchTime.now().uptimeNanoseconds < deadline else { throw failure }
                if untilCancelled {
                    try await Task.sleep(nanoseconds: Self.pollInterval)
                } else {
                    // A sleep of its own, which the caller's cancellation does not cut short.
                    await Task { try? await Task.sleep(nanoseconds: Self.pollInterval) }.value
                }
            }
        }
    }

    func update<T>(wait: Wait, _ body: (RefreshLease.Record?) -> (RefreshLease.Record?, T)) throws -> T {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure(step: "open", code: errno) }
        defer { close(fd) }
        try lock(fd, wait)
        defer { flock(fd, LOCK_UN) }
        let before = try readAll(fd)
        let current: RefreshLease.Record? = before.isEmpty ? nil
            : (try? JSONDecoder().decode(RefreshLease.Record.self, from: before)) ?? RefreshLease.Record(owner: "", expiresAt: .distantPast)
        insideLock?()
        let (next, result) = body(current)
        let after = try next.map { try JSONEncoder().encode($0) } ?? Data()
        if after != before {
            if failsWrites { throw Failure(step: "write", code: EIO) }
            try writeAll(fd, after)
        }
        return result
    }

    /// Takes the exclusive lock as `wait` says. A bounded wait that runs out throws
    /// `Failure(step: "lock", code: EWOULDBLOCK)`, the same as a lock that can't be taken at all.
    private func lock(_ fd: Int32, _ wait: Wait) throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, lockWait) * 1_000_000_000)
        while true {
            if flock(fd, wait == .unbounded ? LOCK_EX : LOCK_EX | LOCK_NB) == 0 { return }
            let code = errno
            if code == EINTR { continue }
            guard wait == .bounded, code == EWOULDBLOCK else { throw Failure(step: "lock", code: code) }
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Failure(step: "lock", code: EWOULDBLOCK) }
            usleep(10_000)
        }
    }

    private func readAll(_ fd: Int32) throws -> Data {
        guard lseek(fd, 0, SEEK_SET) == 0 else { throw Failure(step: "seek", code: errno) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { if errno == EINTR { continue }; throw Failure(step: "read", code: errno) }
            if n == 0 { return data }
            data.append(buffer, count: n)
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) throws {
        guard ftruncate(fd, 0) == 0 else { throw Failure(step: "truncate", code: errno) }
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, off_t(offset)) }
            if n < 0 { if errno == EINTR { continue }; throw Failure(step: "write", code: errno) }
            offset += n
        }
    }
}
