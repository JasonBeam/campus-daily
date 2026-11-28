//
//  CardHistoryDiskCoordinator.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/27.
//

import Foundation

/// Serial coordinator for the app-private campus card history disk cache:
/// `<Application Support>/CardHistory/<sessionID>/cache.v1.json`.
///
/// Security and isolation invariants:
/// - **Sample mode**: `rootDirectory == nil` -> zero disk and zero Keychain touches.
/// - **Committed-epoch gate**: only reads or writes when `shared.sessionEpoch` is readable and
///   in `.active` or `.activePendingClear`. In `.switching`, `.signedOutPendingClear`, `.signedOut`,
///   missing epoch, or Keychain read failure, returns memory-only without touching disk or creating anchors.
/// - **Epoch-bound private anchor**: `StoreKey.cardHistorySession` stores `(epochID, sessionID, salt)`.
///   If `anchor.epochID != currentEpoch.id` (e.g. lock-screen anchor delete failure or crash during
///   `A -> B -> A`), the old session directory is immediately isolated and never opened.
/// - **Lock-screen resilience**: distinguishes `errSecItemNotFound` (`nil`) from Keychain read errors
///   (e.g. `-25308`) and file `ENOENT` from `EPERM`/`EACCES`. Transient lock errors never delete files,
///   never delete anchors, and never mint a new salt/session.
/// - **Task-scoped cleanup**: corrupt-file self-deletion and logout/switch cleanup only delete the
///   exact `<taskSessionID>` after verifying epoch/anchor ownership, never wiping a newer session.
public actor CardHistoryDiskCoordinator: CardHistoryCaching {
    public static let folderName = "CardHistory"
    public static let cacheFileName = "cache.v1.json"

    let store: SecureStore
    let rootDirectory: URL?
    let fileSystem: CardHistoryFileSystem
    private let randomSalt: @Sendable () -> Data?
    private let makeSessionID: @Sendable () -> String
    private let maxDays: Int
    private let maxBytes: Int
    private let maxAge: TimeInterval

    /// Monotonically bumped by `invalidateAndClear()` so any in-flight load/save suspended across
    /// an `await` immediately discards its result.
    var invalidationToken: UInt64 = 0

    /// Test hooks (all nil in production) for deterministic interleaving across awaits.
    var beforeReadFile: (@Sendable (String, String) async -> Void)?
    var beforeWriteFile: (@Sendable (String, String) async -> Void)?
    var beforeSelfDelete: (@Sendable (String, String) async -> Void)?
    var beforeInvalidateRemove: (@Sendable (String) async -> Void)?

    public init(store: SecureStore,
                rootDirectory: URL?,
                fileSystem: CardHistoryFileSystem = LocalCardHistoryFileSystem(),
                randomSalt: @escaping @Sendable () -> Data? = LaundryHistoryStore.randomSalt,
                makeSessionID: @escaping @Sendable () -> String = { UUID().uuidString },
                maxDays: Int = CardHistory.maxCacheDays,
                maxBytes: Int = CardHistory.maxCacheBytes,
                maxAge: TimeInterval = CardHistory.maxCacheAge) {
        self.store = store
        self.rootDirectory = rootDirectory
        self.fileSystem = fileSystem
        self.randomSalt = randomSalt
        self.makeSessionID = makeSessionID
        self.maxDays = maxDays
        self.maxBytes = maxBytes
        self.maxAge = maxAge
    }

    /// Convenience factory for live (`applicationSupport != nil`) vs sample (`nil`).
    public static func forServices(_ services: CampusServices,
                                   fileSystem: CardHistoryFileSystem = LocalCardHistoryFileSystem()) -> CardHistoryDiskCoordinator {
        let root: URL? = services.kind == .live
            ? services.applicationSupport?.appendingPathComponent(folderName, isDirectory: true)
            : nil
        return CardHistoryDiskCoordinator(store: services.secureStore, rootDirectory: root, fileSystem: fileSystem)
    }

    func setHooks(beforeReadFile: (@Sendable (String, String) async -> Void)? = nil,
                  beforeWriteFile: (@Sendable (String, String) async -> Void)? = nil,
                  beforeSelfDelete: (@Sendable (String, String) async -> Void)? = nil,
                  beforeInvalidateRemove: (@Sendable (String) async -> Void)? = nil) {
        self.beforeReadFile = beforeReadFile
        self.beforeWriteFile = beforeWriteFile
        self.beforeSelfDelete = beforeSelfDelete
        self.beforeInvalidateRemove = beforeInvalidateRemove
    }

    // MARK: - Load

    public func load(now: Date, calendar: Calendar, samePerson: @Sendable () async -> Bool) async -> CachedCardHistory? {
        guard let root = rootDirectory else { return nil }
        let startToken = invalidationToken

        guard let context = readCommittedContext() else { return nil }
        let anchorRead = readAnchor()
        let anchor: CardHistorySessionAnchor
        switch anchorRead {
        case .lockedOrError:
            // Lock screen / Keychain error: do NOT delete files or anchors, do NOT mint new salt.
            return nil
        case .missing:
            // Cleanly confirmed no anchor exists: sweep any leftover orphan directories.
            sweepDirectories(in: root, keeping: nil)
            return nil
        case .undecodable:
            // Corrupt anchor: isolate by trying to remove anchor; never open any directory.
            try? store.delete(.cardHistorySession)
            return nil
        case .present(let existing):
            if existing.epochID != context.epoch.id {
                // Epoch mismatch (e.g. A -> B -> A after lock-screen anchor-delete failure or crash):
                // IMMEDIATELY isolate; never open `existing.sessionID` even if `ownerTag` would match.
                try? store.delete(.cardHistorySession)
                if let oldDir = sessionDirectory(root: root, sessionID: existing.sessionID) {
                    try? fileSystem.removeItem(at: oldDir)
                }
                return nil
            }
            anchor = existing
            // Confirmed unlocked with an active valid anchor: opportunistically sweep any older
            // orphan session directories (excluding `anchor.sessionID`).
            sweepDirectories(in: root, keeping: anchor.sessionID)
        }

        let taskEpochID = context.epoch.id
        let taskSessionID = anchor.sessionID
        guard let fileURL = cacheFileURL(root: root, sessionID: taskSessionID) else { return nil }

        if let hook = beforeReadFile {
            await hook(taskEpochID, taskSessionID)
        }
        guard invalidationToken == startToken,
              await samePerson(),
              verifyActiveSession(epochID: taskEpochID, sessionID: taskSessionID) else {
            return nil
        }

        // Enforce the byte budget BEFORE reading the file into memory or invoking JSONDecoder.
        let fileSize: Int64
        do {
            fileSize = try fileSystem.fileSize(at: fileURL)
        } catch {
            if fileSystem.isNotFoundError(error) || fileSystem.isPermissionError(error) {
                // Missing file (normal miss) or lock-screen EPERM/EACCES: never delete anything.
                return nil
            }
            return nil
        }
        if fileSize < 0 || fileSize > Int64(maxBytes) {
            if let hook = beforeSelfDelete {
                await hook(taskEpochID, taskSessionID)
            }
            if invalidationToken == startToken,
               verifyActiveSession(epochID: taskEpochID, sessionID: taskSessionID),
               let dir = sessionDirectory(root: root, sessionID: taskSessionID) {
                try? fileSystem.removeItem(at: dir)
            }
            return nil
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: fileURL)
        } catch {
            if fileSystem.isNotFoundError(error) || fileSystem.isPermissionError(error) {
                // Missing file (normal miss) or lock-screen EPERM/EACCES: never delete anything.
                return nil
            }
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let expectedTag = CardHistory.ownerTag(identity: context.identity, salt: anchor.salt)
        let envelope: CardHistoryDiskEnvelope
        let history: CardHistory
        if data.count <= maxBytes,
           let decoded = try? decoder.decode(CardHistoryDiskEnvelope.self, from: data),
           decoded.schemaVersion == CardHistoryDiskEnvelope.currentSchemaVersion,
           decoded.ownerTag == expectedTag,
           let reconstructed = CardHistory.fromCacheEnvelope(decoded, now: now, calendar: calendar,
                                                             maxDays: maxDays, maxAge: maxAge) {
            envelope = decoded
            history = reconstructed
        } else {
            // File was readable, but oversized, corrupt, schema mismatch, wrong ownerTag, or expired (>30d):
            // self-delete ONLY `taskSessionID` after re-verifying epoch & anchor still match.
            if let hook = beforeSelfDelete {
                await hook(taskEpochID, taskSessionID)
            }
            if invalidationToken == startToken,
               verifyActiveSession(epochID: taskEpochID, sessionID: taskSessionID),
               let dir = sessionDirectory(root: root, sessionID: taskSessionID) {
                try? fileSystem.removeItem(at: dir)
            }
            return nil
        }

        // Final double-check before returning to UI: same person, same epoch, same session, not invalidated.
        guard invalidationToken == startToken,
              await samePerson(),
              verifyActiveSession(epochID: taskEpochID, sessionID: taskSessionID) else {
            return nil
        }
        return CachedCardHistory(history: history,
                                 savedAt: envelope.savedAt,
                                 latestReadAt: envelope.latestReadAt ?? envelope.savedAt,
                                 epochID: taskEpochID,
                                 sessionID: taskSessionID)
    }

    // MARK: - Save

    public func save(_ history: CardHistory,
                     savedAt: Date,
                     latestReadAt: Date,
                     samePerson: @Sendable () async -> Bool) async {
        guard let root = rootDirectory, history.holdsFirstRange else { return }
        let startToken = invalidationToken
        guard await samePerson(), invalidationToken == startToken else { return }
        guard let context = readCommittedContext() else { return }

        let taskEpochID = context.epoch.id
        let anchor: CardHistorySessionAnchor
        var replacedOldSessionID: String?

        switch readAnchor() {
        case .lockedOrError:
            // Lock screen / Keychain error: memory-only, do not delete or mint new anchor.
            return
        case .present(let existing) where existing.epochID == taskEpochID:
            anchor = existing
        case .present(let stale):
            // Old-epoch anchor left behind: delete old anchor, mint brand-new `(taskEpochID, newSessionID, newSalt)`,
            // and verify read-back. Any failure stays strictly memory-only and NEVER writes to `stale.sessionID`.
            replacedOldSessionID = stale.sessionID
            do {
                try store.delete(.cardHistorySession)
            } catch {
                return
            }
            guard let minted = mintAndVerifyAnchor(epochID: taskEpochID) else { return }
            anchor = minted
        case .undecodable:
            do {
                try store.delete(.cardHistorySession)
            } catch {
                return
            }
            guard let minted = mintAndVerifyAnchor(epochID: taskEpochID) else { return }
            anchor = minted
        case .missing:
            guard let minted = mintAndVerifyAnchor(epochID: taskEpochID) else { return }
            anchor = minted
        }

        let ownerTag = CardHistory.ownerTag(identity: context.identity, salt: anchor.salt)
        guard let encoded = history.cacheEnvelope(ownerTag: ownerTag,
                                                  savedAt: savedAt,
                                                  latestReadAt: latestReadAt,
                                                  maxDays: maxDays,
                                                  maxBytes: maxBytes) else {
            return
        }

        if let hook = beforeWriteFile {
            await hook(taskEpochID, anchor.sessionID)
        }

        // Re-verify ownership right before touching disk.
        guard invalidationToken == startToken,
              await samePerson(),
              verifyActiveSession(epochID: taskEpochID, sessionID: anchor.sessionID) else {
            return
        }

        guard let sessionDir = sessionDirectory(root: root, sessionID: anchor.sessionID),
              let fileURL = cacheFileURL(root: root, sessionID: anchor.sessionID) else {
            return
        }
        do {
            try fileSystem.createDirectory(at: root)
            try fileSystem.createDirectory(at: sessionDir)
            try fileSystem.writeProtectedFile(encoded.data, to: fileURL)
        } catch {
            // Any directory/file failure falls back cleanly to memory-only.
            return
        }

        // Best-effort cleanup of replaced or orphaned session directories (never touches `anchor.sessionID`).
        if let oldID = replacedOldSessionID, oldID != anchor.sessionID,
           let oldDir = sessionDirectory(root: root, sessionID: oldID) {
            try? fileSystem.removeItem(at: oldDir)
        }
        sweepDirectories(in: root, keeping: anchor.sessionID)
    }

    // MARK: - Internal helpers

    struct CommittedContext {
        var epoch: SessionEpoch
        var identity: String
    }

    enum AnchorRead {
        case present(CardHistorySessionAnchor)
        case missing
        case undecodable
        case lockedOrError
    }

    func readCommittedContext() -> CommittedContext? {
        let epoch: SessionEpoch?
        do {
            epoch = try SessionEpochStore(store: store).read()
        } catch {
            return nil
        }
        guard let epoch, epoch.allowsRefreshCommit else { return nil }
        guard let identity = readConfirmedIdentity() else { return nil }
        return CommittedContext(epoch: epoch, identity: identity)
    }

    /// Reads the confirmed identity for the currently signed-in person.
    /// Uses non-fallback `cardUnionID` first, falling back to non-empty `account`.
    /// Returns `nil` when Keychain is unreadable or identity is unconfirmed (fallback card + no account).
    private func readConfirmedIdentity() -> String? {
        let vault = StoredSchoolVault(store: store)
        let session: EcyktSession?
        let account: SchoolAccount?
        do {
            session = try vault.ecyktSession()
            account = try vault.account()
        } catch {
            return nil
        }
        if let session, session.cardIsFallback != true, let union = session.cardUnionID, !union.isEmpty {
            return "card:" + union
        }
        if let name = account?.account, !name.isEmpty {
            return "account:" + name
        }
        return nil
    }

    func readAnchor() -> AnchorRead {
        do {
            guard let anchor = try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession) else {
                return .missing
            }
            return anchor.isValid ? .present(anchor) : .undecodable
        } catch let error as StorageError where error.isUndecodable {
            return .undecodable
        } catch {
            return .lockedOrError
        }
    }

    private func mintAndVerifyAnchor(epochID: String) -> CardHistorySessionAnchor? {
        guard let salt = randomSalt(), salt.count == 32 else { return nil }
        let sessionID = makeSessionID()
        guard CardHistorySessionAnchor.isCanonicalSessionID(sessionID) else { return nil }
        let candidate = CardHistorySessionAnchor(epochID: epochID, sessionID: sessionID, salt: salt)
        do {
            try store.writeJSON(candidate, .cardHistorySession)
            guard let readBack = try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession),
                  readBack == candidate else {
                return nil
            }
            return candidate
        } catch {
            return nil
        }
    }

    private func verifyActiveSession(epochID: String, sessionID: String) -> Bool {
        guard let epoch = try? SessionEpochStore(store: store).read(),
              epoch.id == epochID,
              epoch.allowsRefreshCommit else {
            return false
        }
        guard case .present(let anchor) = readAnchor(),
              anchor.epochID == epochID,
              anchor.sessionID == sessionID else {
            return false
        }
        return true
    }

    /// Resolves a canonical UUID session directory strictly one level beneath `root`.
    /// Returns `nil` for any malformed, relative, or escaping session ID so deletes can never
    /// touch sibling files outside `root`.
    func sessionDirectory(root: URL, sessionID: String) -> URL? {
        guard CardHistorySessionAnchor.isCanonicalSessionID(sessionID) else { return nil }
        let cleanRoot = root.standardizedFileURL
        let candidate = cleanRoot.appendingPathComponent(sessionID, isDirectory: true).standardizedFileURL
        guard candidate.deletingLastPathComponent() == cleanRoot,
              candidate.lastPathComponent == sessionID else {
            return nil
        }
        return candidate
    }

    private func cacheFileURL(root: URL, sessionID: String) -> URL? {
        sessionDirectory(root: root, sessionID: sessionID)?.appendingPathComponent(Self.cacheFileName)
    }

    func sweepDirectories(in root: URL, keeping keepSessionID: String?) {
        let cleanRoot = root.standardizedFileURL
        guard let entries = try? fileSystem.listDirectory(at: cleanRoot) else { return }
        for entry in entries {
            let cleanEntry = entry.standardizedFileURL
            guard cleanEntry.deletingLastPathComponent() == cleanRoot else { continue }
            if let keepSessionID, cleanEntry.lastPathComponent == keepSessionID { continue }
            try? fileSystem.removeItem(at: cleanEntry)
        }
    }
}
