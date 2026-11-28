//
//  SessionEpoch.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/26.
//

import Foundation

/// Cross-process session epoch stored in the shared Keychain (`shared.sessionEpoch`).
/// Contains no personal information and no timestamp: only a random epoch identifier and
/// a lifecycle phase.
public struct SessionEpoch: Sendable, Codable, Equatable {
    public enum Phase: String, Sendable, Codable, Equatable, CaseIterable {
        /// Account switch, login commit, or sign-out is in progress; credentials may be mid-transition.
        case switching
        /// New account credentials committed, but `shared.snapshot` has not yet been cleared or replaced.
        case activePendingClear
        /// Normal signed-in state; only snapshots matching `id` are valid.
        case active
        /// Sign-out credentials deleted, but `shared.snapshot` has not yet been cleared.
        case signedOutPendingClear
        /// Signed out and `shared.snapshot` has been cleared.
        case signedOut
    }

    public var id: String
    public var phase: Phase

    public init(id: String = UUID().uuidString, phase: Phase) {
        self.id = id
        self.phase = phase
    }

    /// True only when a snapshot tagged with `id` may be displayed by the app or widget.
    public var allowsSnapshotRead: Bool {
        phase == .active
    }

    /// True when a school refresh for this epoch is permitted to commit a snapshot.
    /// In `.activePendingClear`, a refresh starts from an empty snapshot and advances to `.active`.
    public var allowsRefreshCommit: Bool {
        phase == .active || phase == .activePendingClear
    }

    /// True when the app UI must hide stored account/profile (signed out or mid-switch).
    public var hidesAccountUI: Bool {
        switch phase {
        case .switching, .signedOutPendingClear, .signedOut:
            return true
        case .activePendingClear, .active:
            return false
        }
    }

    /// True when `finishPendingClear` should clear `shared.snapshot` and advance the phase.
    public var needsPendingClear: Bool {
        phase == .activePendingClear || phase == .signedOutPendingClear
    }

    /// The phase after `shared.snapshot` has been cleared/replaced.
    public var clearedPhase: Phase {
        switch phase {
        case .activePendingClear: return .active
        case .signedOutPendingClear: return .signedOut
        case .switching, .active, .signedOut: return phase
        }
    }
}

/// Helper for reading and writing `SessionEpoch` and checking legacy 0.11.5 stale markers.
public struct SessionEpochStore: Sendable {
    public let store: SecureStore

    public init(store: SecureStore) {
        self.store = store
    }

    /// Reads the current `SessionEpoch`, or `nil` on a fresh install / 0.11.5 upgrade.
    /// Throws on Keychain read failure or undecodable data (never falls back to nil on error).
    public func read() throws -> SessionEpoch? {
        try store.readJSON(SessionEpoch.self, .sharedSessionEpoch)
    }

    /// Writes (or deletes when `nil`) the current `SessionEpoch`.
    public func write(_ epoch: SessionEpoch?) throws {
        try store.writeJSON(epoch, .sharedSessionEpoch)
    }

    /// Whether the legacy 0.11.5 `shared.snapshotStale` marker is still present.
    /// Throws on Keychain read failure.
    public func hasLegacyStaleMark() throws -> Bool {
        try store.read(.sharedSnapshotStale) != nil
    }

    /// Best-effort deletion of the legacy 0.11.5 `shared.snapshotStale` marker.
    public func deleteLegacyStaleMark() throws {
        try store.delete(.sharedSnapshotStale)
    }
}
