//
//  WidgetStoredData.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

/// What the widget draws from: the shared snapshot, the saved account, and the session epoch,
/// read together. Before the first unlock after a restart (or when the Keychain refuses a read)
/// nothing can be read; that is not the same as nobody being signed in, and the widget must not
/// draw the signed-out face for it.
public struct WidgetStoredData: Sendable, Equatable {
    public var snapshot: HomeSnapshot?
    public var account: SchoolAccount?
    public var epoch: SessionEpoch?

    /// How soon the widget asks again after a read it couldn't do.
    public static let unreadableRetry: TimeInterval = 5 * 60

    public init(snapshot: HomeSnapshot?, account: SchoolAccount?, epoch: SessionEpoch? = nil) {
        self.snapshot = snapshot; self.account = account; self.epoch = epoch
    }

    /// Nil = the Keychain could not be read now, `shared.sessionEpoch` is undecodable, or the
    /// epoch changed across both lockless sequence-read attempts (fail closed without showing
    /// numbers).
    /// - `.switching`, `.signedOutPendingClear`, `.signedOut`: `snapshot = nil`, `account = nil`.
    /// - `.activePendingClear`: `snapshot = nil`, `account` readable.
    /// - `.active`: `snapshot` readable only when `snapshot.epochID == epoch.id`, `account` readable.
    public static func read(snapshots: SnapshotStoring, vault: SchoolVault) -> WidgetStoredData? {
        do {
            for _ in 0..<2 {
                let epochBefore = try vault.sessionEpoch()
                let legacyStaleBefore: Bool = epochBefore == nil ? try vault.hasLegacyStaleMark() : false
                let snapshot: HomeSnapshot?
                let account: SchoolAccount?
                if let epochBefore {
                    switch epochBefore.phase {
                    case .switching, .signedOutPendingClear, .signedOut:
                        snapshot = nil
                        account = nil
                    case .activePendingClear:
                        snapshot = nil
                        account = try readable { try vault.account() }
                    case .active:
                        let loaded = try readable { try snapshots.loadSnapshot() }
                        snapshot = (loaded?.epochID == epochBefore.id) ? loaded : nil
                        account = try readable { try vault.account() }
                    }
                } else if legacyStaleBefore {
                    snapshot = nil
                    _ = try readable { try vault.account() }
                    account = nil
                } else {
                    let loaded = try readable { try snapshots.loadSnapshot() }
                    snapshot = (loaded?.epochID == nil) ? loaded : nil
                    account = try readable { try vault.account() }
                }
                let epochAfter = try vault.sessionEpoch()
                let legacyStaleAfter: Bool = epochAfter == nil ? try vault.hasLegacyStaleMark() : false
                if epochBefore == epochAfter && legacyStaleBefore == legacyStaleAfter {
                    return WidgetStoredData(snapshot: snapshot, account: account, epoch: epochBefore)
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Rethrows only Keychain failures; a decoding failure becomes nil.
    private static func readable<T>(_ read: () throws -> T?) throws -> T? {
        do { return try read() } catch let e as StorageError where e.status == -1 { return nil }
    }
}
