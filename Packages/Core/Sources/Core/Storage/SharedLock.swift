//
//  SharedLock.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import Foundation

/// The lock around state the app shares with its extensions (the App Group's preferences, its
/// files): what runs in `body` is one read-compare-write the other process can't land in the
/// middle of. In the app it is the refresh lease file's `flock` (`RefreshLease`). A lock that
/// can't be taken throws, and `body` does not run.
public protocol SharedLock: Sendable {
    func locked<T>(_ body: () throws -> T) throws -> T
    /// `locked` for async callers: the wait for the lock suspends instead of holding a thread.
    /// `body` runs in `isolation`, the caller's.
    func lockedWhenFree<T>(isolation: isolated (any Actor)?, _ body: () throws -> T) async throws -> T
    /// `locked` without any wait: throws at once while the lock is taken (the main thread).
    func lockedIfFree<T>(_ body: () throws -> T) throws -> T
}

public extension SharedLock {
    /// A lock that never waits long (`UnsharedLock`, tests' locks): the same as `locked`.
    func lockedWhenFree<T>(isolation: isolated (any Actor)?, _ body: () throws -> T) async throws -> T {
        try locked(body)
    }

    func lockedIfFree<T>(_ body: () throws -> T) throws -> T { try locked(body) }

    /// `lockedWhenFree` in the caller's isolation.
    func lockedWhenFree<T>(_ body: () throws -> T, isolation: isolated (any Actor)? = #isolation) async throws -> T {
        try await lockedWhenFree(isolation: isolation, body)
    }
}
