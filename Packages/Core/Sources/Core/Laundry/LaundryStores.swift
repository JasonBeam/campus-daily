import Foundation

/// `LaundryVault` over a `SecureStore`: `laundry.account` (mobile id + login) and
/// `laundry.checkout` (AfterFirstUnlockThisDeviceOnly, not shared with the widget).
public struct StoredLaundryVault: LaundryVault {
    let store: SecureStore
    public init(store: SecureStore) { self.store = store }

    public func accountItem() throws -> UjingAccountItem? { try store.readJSON(UjingAccountItem.self, .laundryAccount) }
    public func saveAccountItem(_ item: UjingAccountItem?) throws { try store.writeJSON(item, .laundryAccount) }
    public func checkout() throws -> LaundryCheckout? { try store.readJSON(LaundryCheckout.self, .laundryCheckout) }
    public func saveCheckout(_ checkout: LaundryCheckout?) throws { try store.writeJSON(checkout, .laundryCheckout) }
}
