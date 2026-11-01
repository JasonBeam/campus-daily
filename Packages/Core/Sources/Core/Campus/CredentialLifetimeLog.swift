import Foundation

/// The credential-lifetime lines (`school.credentialExpired kind=… ageMinutes=…`) kept on this
/// phone so they can be exported from the app: the system log alone is out of reach without a
/// Mac. Both processes append (the widget refreshes too), so it lives in the shared Keychain
/// item `shared.credentialLog`. Kind and minutes only, never a value; at most `limit` lines,
/// oldest dropped first. Kept across sign-out (it says nothing about the person); reset deletes it.
public struct CredentialLifetimeLog: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let at: Date
        public let event: String
    }

    public static let limit = 50
    /// Longer lines are cut: a lifetime line is about 70 characters.
    static let maxEventLength = 120
    /// Bytes read back at most; anything larger is treated as empty.
    static let maxStoredBytes = 16 * 1024

    let store: SecureStore

    public init(store: SecureStore) { self.store = store }

    /// Adds one line. A Keychain that can't be read or written (before the first unlock) loses
    /// the line; the system log still has it. Two processes appending in the same instant may
    /// lose one of the two lines; this is a diagnostic, not a record.
    public func append(_ event: String, at: Date) {
        var lines = entries()
        lines.append(Entry(at: at, event: String(event.prefix(Self.maxEventLength))))
        if lines.count > Self.limit { lines.removeFirst(lines.count - Self.limit) }
        guard let data = try? JSONEncoder().encode(lines) else { return }
        try? store.write(data, for: .sharedCredentialLog)
    }

    /// Oldest first; empty when nothing was kept or the item can't be read.
    public func entries() -> [Entry] {
        guard let data = (try? store.read(.sharedCredentialLog)) ?? nil, data.count <= Self.maxStoredBytes,
              let lines = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return lines
    }
}
