import Foundation

/// Hot-water persistence (Keychain `water.binding`, `water.session`). Session writes fail
/// closed: the engine runs no side effect after a failed write.
public protocol ShowerVault: Sendable {
    func binding() throws -> ShowerBinding?
    func saveBinding(_ binding: ShowerBinding?) throws
    func showerState() throws -> ShowerState?
    func saveShowerState(_ state: ShowerState?) throws
}
