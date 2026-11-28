//
//  LeaseOwnership.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import Foundation

/// Handed to a credential or snapshot write-back that runs under the refresh lease: the write
/// happens in one locked step with the check that the lease is still ours
/// (`RefreshLease.withOwnership`). Passing `nil` (`LeaseOwnership(nil)` / `.unavailable`) fails
/// closed: every write reports `.lost` and never executes `body`. Tests and sample mode can
/// explicitly opt into an in-memory lock via `.inMemory(_:)` or `.unchecked`.
public struct LeaseOwnership: Sendable {
    private enum Backing: Sendable {
        case leased(RefreshLease)
        case unavailable
        case inMemory(InMemoryCommitLock)
    }

    private let backing: Backing

    /// Fails closed when `lease` is `nil` (or when `lease.file` is `nil`).
    public init(_ lease: RefreshLease?) {
        if let lease {
            self.backing = .leased(lease)
        } else {
            self.backing = .unavailable
        }
    }

    private init(_ backing: Backing) { self.backing = backing }

    /// Fail-closed ownership: every write returns `.lost` without running `body`.
    public static let unavailable = LeaseOwnership(.unavailable)

    /// In-memory commit lock for tests and sample mode (never used in production).
    public static func inMemory(_ lock: InMemoryCommitLock = InMemoryCommitLock()) -> LeaseOwnership {
        LeaseOwnership(.inMemory(lock))
    }

    /// Convenience in-memory ownership for unit tests.
    public static let unchecked = LeaseOwnership(.inMemory(InMemoryCommitLock()))

    /// nil = the lease is not ours any more, the file's lock stayed held for the whole wait,
    /// or the task was cancelled (the widget past its deadline, about to be suspended: it must
    /// not take the file lock now); `body` did not run.
    public func write<T>(isolation: isolated (any Actor)? = #isolation, _ body: () throws -> T) async throws -> T? {
        if case .ran(let value) = try await attempt(retaking: false, body) { return value }
        return nil
    }

    /// `write` for a password login's accepted portal token and the saved account's hold and
    /// pause only: the lease may have run out
    /// while this owner is still the stored one (`RefreshLease.withOwnershipRetaking`). The owner
    /// check stays, and so does the cancellation check: a cancelled task (the widget past its
    /// deadline, about to be suspended) must not take the file lock, so nothing is written.
    func writeRetaking<T>(isolation: isolated (any Actor)? = #isolation, _ body: () throws -> T) async throws -> T? {
        if case .ran(let value) = try await attempt(retaking: true, body) { return value }
        return nil
    }

    /// How long a credential write whose lock wait ran out pauses before its one more try.
    static let lockRetryPause: TimeInterval = 0.5

    /// `write` (`retaking`: `writeRetaking`) for a credential the school already gave (the
    /// portal token after the password, a rotated card session): dropping it costs a login, so a
    /// lock that stayed held for the whole wait is tried once more after `lockRetryPause`
    /// (suspended). `.lockTimeout` when it is still held then, or the task was cancelled during
    /// the pause: the caller logs it. `.lost` as for `write`. Never written without the lease.
    func writeRetryingLockTimeout<T>(isolation: isolated (any Actor)? = #isolation, retaking: Bool,
                                     _ body: () throws -> T) async throws -> RefreshLease.Owned<T> {
        let first = try await attempt(retaking: retaking, body)
        guard case .lockTimeout = first else { return first }
        guard (try? await Task.sleep(nanoseconds: UInt64(Self.lockRetryPause * 1_000_000_000))) != nil else { return first }
        return try await attempt(retaking: retaking, body)
    }

    /// One try: `.lost` without the lease (or cancelled), `.lockTimeout` when the lock stayed
    /// held for the whole wait. Either way `body` did not run.
    func attempt<T>(isolation: isolated (any Actor)? = #isolation, retaking: Bool,
                    _ body: () throws -> T) async throws -> RefreshLease.Owned<T> {
        switch backing {
        case .unavailable:
            return .lost
        case .inMemory(let lock):
            guard !Task.isCancelled else { return .lost }
            return .ran(try lock.locked(body))
        case .leased(let lease):
            guard !Task.isCancelled else { return .lost }
            return try await lease.withOwnership(waitingAtMost: lease.lockWait, retaking: retaking, body)
        }
    }
}
