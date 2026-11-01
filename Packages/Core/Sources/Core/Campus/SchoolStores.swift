import Foundation

/// `SchoolVault` over a `SecureStore` (Keychain in the app, in-memory in tests).
public struct StoredSchoolVault: SchoolVault {
    let store: SecureStore
    public init(store: SecureStore) { self.store = store }

    private struct PortalBox: Codable { var token: String; var expiresAt: Date?; var obtainedAt: Date? }

    public func portalToken() throws -> PortalToken? {
        try store.readJSON(PortalBox.self, .schoolPortal).map { PortalToken($0.token, expiresAt: $0.expiresAt, obtainedAt: $0.obtainedAt) }
    }
    public func savePortalToken(_ token: PortalToken?) throws {
        try store.writeJSON(token.map { PortalBox(token: $0.value, expiresAt: $0.expiresAt, obtainedAt: $0.obtainedAt) }, .schoolPortal)
    }
    public func ecyktSession() throws -> EcyktSession? { try store.readJSON(EcyktSession.self, .schoolEcykt) }
    public func saveEcyktSession(_ session: EcyktSession?) throws { try store.writeJSON(session, .schoolEcykt) }
    public func profile() throws -> SchoolProfile? { try store.readJSON(SchoolProfile.self, .schoolProfile) }
    public func saveProfile(_ profile: SchoolProfile?) throws { try store.writeJSON(profile, .schoolProfile) }
    public func account() throws -> SchoolAccount? { try store.readJSON(SchoolAccount.self, .schoolPassword) }
    public func saveAccount(_ account: SchoolAccount?) throws { try store.writeJSON(account, .schoolPassword) }

    private struct DeviceBox: Codable { var id: String }
    public func loginDeviceID() throws -> String? { try store.readJSON(DeviceBox.self, .schoolDevice)?.id }
    public func saveLoginDeviceID(_ id: String?) throws { try store.writeJSON(id.map(DeviceBox.init), .schoolDevice) }

    public func credentialBytes() throws -> [Data?] {
        [try store.read(.schoolEcykt), try store.read(.schoolPortal), try store.read(.schoolPassword)]
    }
}
