import Foundation

/// Whether a start below zero is allowed on this phone: one Keychain item that never leaves
/// the device (`StoreKey.showerStartMode`), cleared by 重置校日常, kept by 退出登录.
public struct ShowerStartOverrideStore: Sendable {
    let store: SecureStore
    public init(store: SecureStore) { self.store = store }

    private static let on = Data("allowsDebt".utf8)

    /// Off when absent or unreadable.
    public var isOn: Bool { ((try? store.read(.showerStartMode)) ?? nil) == Self.on }

    public func set(_ on: Bool) throws {
        if on { try store.write(Self.on, for: .showerStartMode) } else { try store.delete(.showerStartMode) }
    }
}
