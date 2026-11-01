import Foundation

/// Laundry persistence (Keychain `laundry.account`, `laundry.checkout`). Checkout writes fail
/// closed: the engine runs no side effect after a failed write.
public protocol LaundryVault: Sendable {
    func accountItem() throws -> UjingAccountItem?
    func saveAccountItem(_ item: UjingAccountItem?) throws
    func checkout() throws -> LaundryCheckout?
    func saveCheckout(_ checkout: LaundryCheckout?) throws
}

public extension LaundryVault {
    /// The per-install `x-mobile-id`: created once (UUID) and kept across logins/logouts.
    func mobileID(make: () -> String = { UUID().uuidString }) throws -> String {
        if let item = try accountItem() { return item.mobileID }
        let id = make()
        try saveAccountItem(UjingAccountItem(mobileID: id))
        return id
    }

    func account() throws -> UjingAccount? { try accountItem()?.account }

    /// Stores (or clears) the login, keeping the install's mobile id.
    func saveAccount(_ account: UjingAccount?) throws {
        let id = try mobileID()
        try saveAccountItem(UjingAccountItem(mobileID: id, account: account))
    }
}
