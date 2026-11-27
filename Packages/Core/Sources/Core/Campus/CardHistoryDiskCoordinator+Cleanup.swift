//
//  CardHistoryDiskCoordinator+Cleanup.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/27.
//

import Foundation

extension CardHistoryDiskCoordinator {
    /// Invalidates all in-flight tasks, deletes `cardHistory.session` first (blocking reads immediately),
    /// and removes only the captured previous session directory (never wiping a newer session).
    public func invalidateAndClear() async {
        invalidationToken &+= 1
        guard let root = rootDirectory else { return }

        let oldSessionID: String?
        switch readAnchor() {
        case .present(let existing): oldSessionID = existing.sessionID
        case .missing, .undecodable, .lockedOrError: oldSessionID = nil
        }

        // Delete anchor FIRST so reads are blocked even if directory deletion fails.
        try? store.delete(.cardHistorySession)

        guard let oldSessionID else { return }
        if let hook = beforeInvalidateRemove {
            await hook(oldSessionID)
        }
        guard !isCurrentActiveSession(oldSessionID),
              let oldDir = sessionDirectory(root: root, sessionID: oldSessionID) else { return }
        try? fileSystem.removeItem(at: oldDir)
    }

    /// Invalidates and cleans up a previous-epoch anchor and orphan directories after an account
    /// switch without touching a valid anchor already minted for the current epoch.
    public func invalidateStaleSession() async {
        guard let root = rootDirectory else { return }

        let epoch: SessionEpoch?
        do {
            epoch = try SessionEpochStore(store: store).read()
        } catch let error as StorageError where error.isUndecodable {
            epoch = nil
        } catch {
            return
        }

        switch readAnchor() {
        case .lockedOrError:
            return
        case .missing:
            sweepDirectories(in: root, keeping: nil)
        case .undecodable:
            invalidationToken &+= 1
            try? store.delete(.cardHistorySession)
            sweepDirectories(in: root, keeping: nil)
        case .present(let anchor):
            if let epoch, epoch.allowsRefreshCommit, anchor.epochID == epoch.id {
                sweepDirectories(in: root, keeping: anchor.sessionID)
            } else {
                invalidationToken &+= 1
                try? store.delete(.cardHistorySession)
                if let hook = beforeInvalidateRemove {
                    await hook(anchor.sessionID)
                }
                if !isCurrentActiveSession(anchor.sessionID),
                   let oldDir = sessionDirectory(root: root, sessionID: anchor.sessionID) {
                    try? fileSystem.removeItem(at: oldDir)
                }
                await sweepOrphans()
            }
        }
    }

    /// Sweeps orphan session directories once unlocked (launch, foreground, page open).
    /// Skips completely if `shared.sessionEpoch` or `cardHistory.session` cannot be read (locked).
    public func sweepOrphans() async {
        guard let root = rootDirectory else { return }

        let epoch: SessionEpoch?
        do {
            epoch = try SessionEpochStore(store: store).read()
        } catch let error as StorageError where error.isUndecodable {
            epoch = nil
        } catch {
            // Keychain locked or unreadable: never delete anything.
            return
        }

        let anchorRead = readAnchor()
        let keepSessionID: String?
        switch anchorRead {
        case .lockedOrError:
            // Keychain locked: skip sweep completely, never delete active data.
            return
        case .missing:
            keepSessionID = nil
        case .undecodable:
            try? store.delete(.cardHistorySession)
            keepSessionID = nil
        case .present(let anchor):
            if let epoch, epoch.allowsRefreshCommit, anchor.epochID == epoch.id {
                keepSessionID = anchor.sessionID
            } else {
                // Signed out, switching, or old-epoch anchor: delete stale anchor and sweep everything.
                try? store.delete(.cardHistorySession)
                keepSessionID = nil
            }
        }
        sweepDirectories(in: root, keeping: keepSessionID)
    }

    func isCurrentActiveSession(_ sessionID: String) -> Bool {
        guard let epoch = try? SessionEpochStore(store: store).read(),
              epoch.allowsRefreshCommit,
              case .present(let current) = readAnchor(),
              current.epochID == epoch.id,
              current.sessionID == sessionID else {
            return false
        }
        return true
    }
}
