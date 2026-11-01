import Foundation

/// Hot-water persistence (Keychain `water.binding`, `water.session`). Session writes fail
/// closed: the engine runs no side effect after a failed write.
public protocol ShowerVault: Sendable {
    func binding() throws -> ShowerBinding?
    func saveBinding(_ binding: ShowerBinding?) throws
    func showerState() throws -> ShowerState?
    func saveShowerState(_ state: ShowerState?) throws
}

extension ShowerVault {
    /// The way out of a saved record that can't be decoded, once the user checked the school's
    /// record: it is removed only while it still can't be read. True when it was removed; false
    /// when there is no record or it reads (then it is kept). A Keychain error is thrown.
    public func clearUnreadableRecord() throws -> Bool {
        do {
            _ = try showerState()
            return false
        } catch ShowerEngineError.unreadableRecord {
            try saveShowerState(nil)
            return true
        }
    }
}
