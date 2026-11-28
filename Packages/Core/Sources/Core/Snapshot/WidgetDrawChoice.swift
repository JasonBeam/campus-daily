//
//  WidgetDrawChoice.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import Foundation

/// What the widget draws from one read of the Keychain (`WidgetStoredData.read`). Numbers come
/// only from a read that went through, the session epoch included; a read that could not be done
/// draws no one's numbers (not the signed-out face either) and asks again soon. Nothing drawn
/// earlier by the process stands in for it: it was checked against neither the epoch nor the
/// person signed in now.
public enum WidgetDrawChoice: Sendable, Equatable {
    case draw(snapshot: HomeSnapshot?, account: SchoolAccount?)
    case noNumbers(retryAfter: TimeInterval)

    public static func choose(_ stored: WidgetStoredData?) -> WidgetDrawChoice {
        guard let stored else { return .noNumbers(retryAfter: WidgetStoredData.unreadableRetry) }
        return .draw(snapshot: stored.snapshot, account: stored.account)
    }

    /// Pre-completion epoch re-check for both `getSnapshot` and `getTimeline`.
    /// Re-reads `shared.sessionEpoch` (and legacy `shared.snapshotStale`) immediately before
    /// handing entries to WidgetKit's completion handler:
    /// - If Keychain is unreadable (or epoch undecodable): `.noNumbers(retryAfter:)`, `drawn: nil`.
    /// - If `currentEpoch` changed (`id` or `phase`) vs `initialEpoch`: discards old
    ///   `initial`/`drawn` and does one offline re-read via `WidgetStoredData.read` to rebuild
    ///   cleanly (returning `.noNumbers(retryAfter:)` if still inconsistent or unreadable).
    /// - If the epoch is unchanged and `drawn` is non-empty, verifies `drawn.epochID` matches
    ///   `currentEpoch.id` (or `nil` on legacy 0.11.5 upgrade), rebuilding offline on mismatch.
    public static func verifiedForCompletion(
        initial: WidgetDrawChoice,
        initialEpoch: SessionEpoch? = nil,
        drawn: HomeSnapshot?,
        snapshots: SnapshotStoring,
        vault: SchoolVault
    ) -> (choice: WidgetDrawChoice, drawn: HomeSnapshot?) {
        guard case .draw(_, let initialAccount) = initial else {
            return (initial, nil)
        }
        let currentEpoch: SessionEpoch?
        let currentLegacyStale: Bool
        do {
            currentEpoch = try vault.sessionEpoch()
            currentLegacyStale = currentEpoch == nil ? try vault.hasLegacyStaleMark() : false
        } catch {
            return (.noNumbers(retryAfter: WidgetStoredData.unreadableRetry), nil)
        }
        if currentEpoch != initialEpoch {
            return rebuildOffline(snapshots: snapshots, vault: vault)
        }
        if let currentEpoch {
            switch currentEpoch.phase {
            case .switching, .signedOutPendingClear, .signedOut:
                return (.draw(snapshot: nil, account: nil), nil)
            case .activePendingClear:
                return (.draw(snapshot: nil, account: initialAccount), nil)
            case .active:
                if let drawn, !drawn.isEmpty {
                    guard drawn.epochID == currentEpoch.id else {
                        return rebuildOffline(snapshots: snapshots, vault: vault)
                    }
                    return (.draw(snapshot: drawn, account: initialAccount), drawn)
                }
                return (.draw(snapshot: nil, account: initialAccount), nil)
            }
        }
        // Legacy 0.11.5 upgrade (`currentEpoch == nil && initialEpoch == nil`).
        if currentLegacyStale {
            return (.draw(snapshot: nil, account: nil), nil)
        }
        if let drawn, !drawn.isEmpty {
            guard drawn.epochID == nil else {
                return rebuildOffline(snapshots: snapshots, vault: vault)
            }
            return (.draw(snapshot: drawn, account: initialAccount), drawn)
        }
        return (.draw(snapshot: nil, account: initialAccount), nil)
    }

    private static func rebuildOffline(
        snapshots: SnapshotStoring,
        vault: SchoolVault
    ) -> (choice: WidgetDrawChoice, drawn: HomeSnapshot?) {
        let rebuilt = WidgetStoredData.read(snapshots: snapshots, vault: vault)
        let choice = WidgetDrawChoice.choose(rebuilt)
        if case .draw(let rebuiltSnapshot, _) = choice {
            return (choice, rebuiltSnapshot)
        }
        return (choice, nil)
    }
}
