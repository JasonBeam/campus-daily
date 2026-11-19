import Foundation
import CryptoKit
#if canImport(Security)
import Security
#endif

// Finished laundry orders kept on the phone for 最近 and 订单 (architecture §3.2, §4.1).

/// An order the engine just saw end, with its raw ids. Handed to the store, never stored as is.
public struct LaundryFinishedOrder: Sendable, Equatable {
    public var orderID: String
    /// The U净 account (`UjingAccount.id`) it belongs to.
    public var accountID: String
    /// The local confirm time (the open order's row shows the same).
    public var at: Date
    public var program: String
    public var machine: String
    public var status: LaundryOrderStatus
    /// U净's pay price from the terminal 50 read; nil otherwise.
    public var amount: Money?
    public init(orderID: String, accountID: String, at: Date, program: String, machine: String,
                status: LaundryOrderStatus, amount: Money?) {
        self.orderID = orderID; self.accountID = accountID; self.at = at; self.program = program
        self.machine = machine; self.status = status; self.amount = amount
    }
}

/// One stored finished order (Keychain `laundry.history`). `key` and `owner` are salted tags of
/// the order id and the account id; no raw id, link, token or reply is kept.
public struct LaundryHistoryEntry: Sendable, Equatable, Codable {
    public var key: String
    public var owner: String
    public var at: Date
    public var program: String
    public var machine: String
    /// "50", "51", "52" or "53".
    public var status: String
    public var amount: Money?
    public init(key: String, owner: String, at: Date, program: String, machine: String, status: String, amount: Money?) {
        self.key = key; self.owner = owner; self.at = at; self.program = program
        self.machine = machine; self.status = status; self.amount = amount
    }
}

public enum LaundryHistory {
    /// Entries are shown and kept for 7 days from the order's confirm time.
    public static let keep: TimeInterval = 7 * 24 * 3600
    /// At most this many entries, newest first.
    public static let cap = 30

    /// The order this step ended, or nil. Only a terminal order read (or pre-start read) of the
    /// record's own order (the candidate during reconcile) on its machine and program, when the
    /// step cleared the record with that outcome or moved it into `attention` (52). The machine,
    /// program and confirm time come from `before`: the cleared record has none. `accountID`:
    /// the engine's signed-in account, for records saved before the account was kept.
    public static func finished(before: LaundryCheckout, event: LaundryEvent, after: LaundryCheckout,
                                accountID: String?) -> LaundryFinishedOrder? {
        let order: LaundryOrder
        switch event {
        case .orderRead(let read, _): order = read
        case .startCheckRead(let check, _): order = check.order
        default: return nil
        }
        guard order.status.isTerminal else { return nil }
        let expected = before.phase == .reconcile ? before.candidateOrderID : before.orderID
        guard let expected, order.id == expected, LaundryReducer.belongs(order, before),
              let draft = before.draft, let at = before.createdAt,
              let owner = before.accountID ?? accountID else { return nil }
        let cleared = after.phase == .none && after.lastOutcome?.orderID == order.id && after.lastOutcome != before.lastOutcome
        let attention = after.phase == .attention && before.phase != .attention
        guard cleared || attention else { return nil }
        let amount = order.status.isDone ? order.price.flatMap { $0.fen > 0 ? $0 : nil } : nil
        return LaundryFinishedOrder(orderID: order.id, accountID: owner, at: at, program: draft.program.name,
                                    machine: draft.machineName, status: order.status, amount: amount)
    }

    /// `entries` with `adding` put in (replacing the one with its key), without entries older
    /// than `keep` or dated after `now`, newest first, at most `cap`.
    public static func merged(_ entries: [LaundryHistoryEntry], adding: LaundryHistoryEntry?, now: Date) -> [LaundryHistoryEntry] {
        var list = entries
        if let adding {
            list.removeAll { $0.key == adding.key }
            list.append(adding)
        }
        return Array(fresh(list, now: now).sorted { $0.at > $1.at }.prefix(cap))
    }

    /// The entries `owner` sees now: theirs, inside the 7 days, not the open order's (`hiding`).
    public static func visible(_ entries: [LaundryHistoryEntry], owner: String, now: Date,
                               hiding key: String? = nil) -> [LaundryHistoryEntry] {
        merged(entries.filter { $0.owner == owner && $0.key != key }, adding: nil, now: now)
    }

    static func fresh(_ entries: [LaundryHistoryEntry], now: Date) -> [LaundryHistoryEntry] {
        entries.filter { $0.at <= now && now.timeIntervalSince($0.at) <= keep }
    }
}

/// Where the engine files a finished order. A failure never blocks the order flow.
public protocol LaundryHistoryRecording: Sendable {
    func record(_ order: LaundryFinishedOrder, now: Date) throws
}

public enum LaundryHistoryError: Error, Equatable, Sendable {
    /// Entries are stored but their salt is gone or unreadable: they are hidden and kept as they are.
    case saltMissing
}

/// `laundry.history` and its salt `laundry.historySalt` over a `SecureStore` (both in the app's
/// private group). The salt is 32 random bytes made with the first entry and kept per install;
/// it is never made again while entries are stored. Any read failure shows nothing.
public struct LaundryHistoryStore: LaundryHistoryRecording {
    let store: SecureStore
    let random: @Sendable () -> Data?

    public init(store: SecureStore, random: @escaping @Sendable () -> Data? = LaundryHistoryStore.randomSalt) {
        self.store = store; self.random = random
    }

    public func record(_ order: LaundryFinishedOrder, now: Date) throws {
        let salt = try saltForWriting()
        let entries = try store.readJSON([LaundryHistoryEntry].self, .laundryHistory) ?? []
        let entry = LaundryHistoryEntry(key: Self.tag("order:" + order.orderID, salt: salt),
                                        owner: Self.tag("account:" + order.accountID, salt: salt),
                                        at: order.at, program: order.program, machine: order.machine,
                                        status: order.status.code, amount: order.status.isDone ? order.amount : nil)
        try store.writeJSON(LaundryHistory.merged(entries, adding: entry, now: now), .laundryHistory)
    }

    /// `accountID`'s entries now, without the open order's (`openOrderID`). Empty when signed out
    /// or when anything can't be read.
    public func entries(accountID: String?, openOrderID: String?, now: Date) -> [LaundryHistoryEntry] {
        guard let accountID, let salt = try? storedSalt(),
              let entries = try? store.readJSON([LaundryHistoryEntry].self, .laundryHistory) else { return [] }
        return LaundryHistory.visible(entries, owner: Self.tag("account:" + accountID, salt: salt), now: now,
                                      hiding: openOrderID.map { Self.tag("order:" + $0, salt: salt) })
    }

    /// Deletes the entries; the salt stays.
    public func clear() throws { try store.delete(.laundryHistory) }

    /// HMAC-SHA256(salt, value), hex.
    public static func tag(_ value: String, salt: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: salt))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// The stored salt, or nil when none was made yet. A salt of the wrong size is unreadable.
    func storedSalt() throws -> Data? {
        guard let salt = try store.read(.laundryHistorySalt) else { return nil }
        guard salt.count == 32 else { throw LaundryHistoryError.saltMissing }
        return salt
    }

    /// The salt, made now only when no entries are stored either.
    private func saltForWriting() throws -> Data {
        if let salt = try storedSalt() { return salt }
        guard try store.read(.laundryHistory) == nil else { throw LaundryHistoryError.saltMissing }
        guard let salt = random(), salt.count == 32 else { throw LaundryHistoryError.saltMissing }
        try store.write(salt, for: .laundryHistorySalt)
        return salt
    }

    public static let randomSalt: @Sendable () -> Data? = {
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        #else
        var rng = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = rng.next() }
        #endif
        return Data(bytes)
    }
}
