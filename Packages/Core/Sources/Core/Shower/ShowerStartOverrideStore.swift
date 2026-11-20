import Foundation

/// Whether a start below zero is allowed on this phone: one Keychain item that never leaves
/// the device (`StoreKey.showerStartMode`), cleared by 重置校日常, kept by 退出登录.
public struct ShowerStartOverrideStore: Sendable {
    let store: SecureStore
    public init(store: SecureStore) { self.store = store }

    /// Off when absent or unreadable.
    // Red-phase stub: always off.
    public var isOn: Bool { false }

    // Red-phase stub: writes nothing.
    public func set(_ on: Bool) throws {}
}
