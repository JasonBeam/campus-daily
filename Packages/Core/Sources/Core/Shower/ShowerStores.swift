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
    /// `water.retained`, the rows this build can read. A row it can't read (written by another
    /// build) is skipped and stays stored; a value that is not a list throws.
    public func retainedShowers() throws -> [ShowerState] { try kept().compactMap { $0?.state } }

    /// Only by `keptFor`: a row without it is nobody's, whatever student the record names.
    public func retainedShowersForBinding() throws -> [ShowerState] {
        guard let student = try binding()?.studentId else { return [] }
        return try kept().compactMap { $0 }.filter { $0.studentId == student }.map(\.state)
    }

    /// Appends the new row after the bytes already stored, which are never re-encoded: a row
    /// this build can't read stays as it was and gets no owner. Nothing is written over a value
    /// that is not a list, or when the record is kept already.
    public func retainShower(_ state: ShowerState) throws {
        let old = try store.read(.showerRetained)
        let rows = try Self.rows(old)
        guard !rows.contains(where: { $0?.state == state }) else { return }
        let student = try binding()?.studentId
        let row: Data
        do { row = try JSONEncoder().encode(KeptShower(state: state, studentId: student)) }
        catch { throw StorageError(operation: "encode \(StoreKey.showerRetained.rawValue)", status: -1) }
        let list = Self.appending(row, to: old, count: rows.count)
        try store.write(list, for: .showerRetained)
        // Read back: the next use goes ahead only when the record is surely kept.
        guard let back = try store.read(.showerRetained), back == list,
              let after = try? Self.rows(back), after.count == rows.count + 1,
              let last = after.last ?? nil, last.state == state, last.studentId == student
        else { throw ShowerEngineError.storage }
    }

    /// `list` (a JSON array of `count` elements) up to its closing bracket, then `row`; the
    /// whitespace after the bracket is dropped.
    static func appending(_ row: Data, to list: Data?, count: Int) -> Data {
        var out = Data("[".utf8)
        if let list {
            let bytes = [UInt8](list)
            var end = bytes.count
            while end > 0, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[end - 1]) { end -= 1 }
            out = Data(bytes[..<(end - 1)])
            if count > 0 { out.append(UInt8(ascii: ",")) }
        }
        out.append(row)
        out.append(UInt8(ascii: "]"))
        return out
    }

    private func kept() throws -> [KeptShower?] { try Self.rows(store.read(.showerRetained)) }

    /// One entry per element, nil for one that isn't a kept record this build reads.
    private static func rows(_ data: Data?) throws -> [KeptShower?] {
        guard let data else { return [] }
        do { return try JSONDecoder().decode([KeptRow].self, from: data).map(\.kept) }
        catch { throw ShowerEngineError.unreadableRecord }
    }
}

/// An element of `water.retained`; never fails, so one row can't make the list unreadable.
private struct KeptRow: Decodable {
    let kept: KeptShower?
    init(from decoder: Decoder) { kept = try? KeptShower(from: decoder) }
}

/// A kept record and the student it was billed to (the binding's, when it was kept). One JSON
/// object: the record's own fields plus `keptFor`, so a list without it still reads.
private struct KeptShower: Codable {
    var state: ShowerState
    var studentId: String?

    private enum Key: String, CodingKey { case keptFor }

    init(state: ShowerState, studentId: String?) { self.state = state; self.studentId = studentId }

    init(from decoder: Decoder) throws {
        state = try ShowerState(from: decoder, live: false)
        studentId = try decoder.container(keyedBy: Key.self).decodeIfPresent(String.self, forKey: .keptFor)
    }

    func encode(to encoder: Encoder) throws {
        try state.encode(to: encoder)
        var fields = encoder.container(keyedBy: Key.self)
        try fields.encodeIfPresent(studentId, forKey: .keptFor)
    }
}
