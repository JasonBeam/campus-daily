//
//  LeaseOwnership.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import Foundation

/// Handed to a credential or snapshot write-back that runs under the refresh lease: the write
/// happens in one locked step with the check that the lease is still ours
/// (`RefreshLease.withOwnership`). Without a lease (tests, previews, an app with no container
/// for its lease file) it just runs. The wait for the file's lock suspends the caller (an
/// actor's step stays on that actor, `body` runs there inside the lock) and holds no thread;
/// it ends after the lease's `lockWait`.
public struct LeaseOwnership: Sendable {
    let lease: RefreshLease?

    public init(_ lease: RefreshLease?) { self.lease = lease }

    public static let unchecked = LeaseOwnership(nil)

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
        guard let lease else { return .ran(try body()) }
        guard !Task.isCancelled else { return .lost }
        return try await lease.withOwnership(waitingAtMost: lease.lockWait, retaking: retaking, body)
    }
}
