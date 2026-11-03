import Foundation

/// A washer the user saved by scanning its code (UI preference, not a credential).
public struct SavedWasher: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var qrCode: String
    public var name: String
    public var savedAt = Date()

    public init(id: String, qrCode: String, name: String, savedAt: Date = Date()) {
        self.id = id; self.qrCode = qrCode; self.name = name; self.savedAt = savedAt
    }

    /// The list with this machine saved: renamed in place when it is there already (keeping when
    /// it was first saved), otherwise appended.
    public static func saving(id: String, qrCode: String, name: String, in list: [SavedWasher],
                              now: Date = Date()) -> [SavedWasher] {
        var list = list
        if let index = list.firstIndex(where: { $0.id == id }) {
            list[index] = SavedWasher(id: id, qrCode: qrCode, name: name, savedAt: list[index].savedAt)
        } else {
            list.append(SavedWasher(id: id, qrCode: qrCode, name: name, savedAt: now))
        }
        return list
    }
}
