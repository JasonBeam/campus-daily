//
//  SchoolVault.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

/// Persistence the school engine needs. Implemented by `StoredSchoolVault` (SchoolStores.swift) and by
/// in-memory fakes. Writes throw so callers can fail closed.
public protocol SchoolVault: Sendable {
    func portalToken() throws -> PortalToken?
    func savePortalToken(_ token: PortalToken?) throws
    func ecyktSession() throws -> EcyktSession?
    func saveEcyktSession(_ session: EcyktSession?) throws
    func profile() throws -> SchoolProfile?
    func saveProfile(_ profile: SchoolProfile?) throws
    func account() throws -> SchoolAccount?
    func saveAccount(_ account: SchoolAccount?) throws
    func loginDeviceID() throws -> String?
    func saveLoginDeviceID(_ id: String?) throws
    /// The card session, portal token and account exactly as stored (bytes, not decoded; nil =
    /// absent): what a login compares before it writes over them. Throws only when the store
    /// can't be read, never because an item no longer decodes.
    func credentialBytes() throws -> [Data?]
    /// Hides the shared snapshot from every reader until a snapshot write goes through
    /// (`SharedSnapshotStore`): someone else is signing in, or the person is signing out.
    func markSnapshotStale(since: Date) throws
}

public extension SchoolVault {
    /// Whether a card session is stored: nil when that can't be told (the Keychain refused the
    /// read, before the first unlock say, or the item no longer decodes). Only false is "signed out".
    func cardSessionStored() -> Bool? {
        do { return try ecyktSession() != nil } catch { return nil }
    }
}
