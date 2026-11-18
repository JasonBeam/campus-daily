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
    /// Throws `ShowerEngineError.unreadableRecord` when the record is there but can't be decoded.
    public func showerState() throws -> ShowerState? {
        guard let data = try store.read(.showerSession) else { return nil }
        do { return try JSONDecoder().decode(ShowerState.self, from: data) }
        catch { throw ShowerEngineError.unreadableRecord }
    }
    public func saveShowerState(_ state: ShowerState?) throws { try store.writeJSON(state, .showerSession) }
    /// `water.retained`. A list that can't be decoded throws, so nothing is added over it.
    public func retainedShowers() throws -> [ShowerState] { try kept().map(\.state) }

    public func retainedShowersForBinding() throws -> [ShowerState] {
        guard let student = try binding()?.studentId else { return [] }
        return try kept().filter { $0.studentId == student }.map(\.state)
    }

    public func retainShower(_ state: ShowerState) throws {
        var kept = try kept()
        guard !kept.contains(where: { $0.state == state }) else { return }
        kept.append(KeptShower(state: state, studentId: try binding()?.studentId))
        try store.writeJSON(kept, .showerRetained)
        // Read back: the next use goes ahead only when the record is surely kept.
        guard try retainedShowers().contains(state) else { throw ShowerEngineError.storage }
    }

    private func kept() throws -> [KeptShower] {
        guard let data = try store.read(.showerRetained) else { return [] }
        do { return try JSONDecoder().decode([KeptShower].self, from: data) }
        catch { throw ShowerEngineError.unreadableRecord }
    }
}

/// A kept record and the student it was billed to (the binding's, when it was kept). One JSON
/// object: the record's own fields plus `keptFor`, so a list without it still reads.
private struct KeptShower: Codable {
    var state: ShowerState
    var studentId: String?

    private enum Key: String, CodingKey { case keptFor }

    init(state: ShowerState, studentId: String?) { self.state = state; self.studentId = studentId }

    init(from decoder: Decoder) throws {
        state = try ShowerState(from: decoder)
        studentId = try decoder.container(keyedBy: Key.self).decodeIfPresent(String.self, forKey: .keptFor)
    }

    func encode(to encoder: Encoder) throws {
        try state.encode(to: encoder)
        var fields = encoder.container(keyedBy: Key.self)
        try fields.encodeIfPresent(studentId, forKey: .keptFor)
    }
}
