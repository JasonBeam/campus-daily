import Foundation

/// `ShowerVault` over a `SecureStore`: `water.binding` and `water.session`
/// (AfterFirstUnlockThisDeviceOnly, not shared with the widget). Writes throw (fail closed).
public struct StoredShowerVault: ShowerVault {
    let store: SecureStore
    public init(store: SecureStore) { self.store = store }

    /// Bindings saved while the app could go through the online access service carry an `access`
    /// object with that service's token. It is ignored when decoding (the binding goes direct);
    /// the first read saves the binding again so the old token leaves the Keychain.
    public func binding() throws -> ShowerBinding? {
        guard let data = try store.read(.showerBinding) else { return nil }
        let binding: ShowerBinding
        do { binding = try JSONDecoder().decode(ShowerBinding.self, from: data) }
        catch { throw StorageError(operation: "decode \(StoreKey.showerBinding.rawValue)", status: -1) }
        if Self.hasLegacyAccess(data) { try? saveBinding(binding) }
        return binding
    }

    static func hasLegacyAccess(_ data: Data) -> Bool {
        guard case .object(let fields)? = try? JSONValue.parse(data) else { return false }
        return fields["access"] != nil
    }
    public func saveBinding(_ binding: ShowerBinding?) throws { try store.writeJSON(binding, .showerBinding) }
    public func showerState() throws -> ShowerState? { try store.readJSON(ShowerState.self, .showerSession) }
    public func saveShowerState(_ state: ShowerState?) throws { try store.writeJSON(state, .showerSession) }
}
