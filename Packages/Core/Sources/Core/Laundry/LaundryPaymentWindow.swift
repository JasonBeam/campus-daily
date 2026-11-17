import Foundation

/// 立刻洗衣's short window after the Alipay launch, in which the app may read the order and
/// start the machine out of the front (`LaundryEngine.openPaymentWindow`). Captured from the
/// order as it is paid; never renewed, never kept across launches. iOS may end it sooner.
public struct LaundryPaymentWindow: Sendable, Equatable {
    /// The longest window asked for. Not a promise: iOS may take the time back sooner.
    public static let maxDuration: TimeInterval = 45

    public let orderID: String
    public let createdAt: Date
    public let accountID: String
    /// The engine it was opened with: a rebuilt engine (another account, a reset) ends it.
    public let engineGeneration: Int
    public let until: Date

    /// Nil unless `record` is a 立刻洗衣 order, not tried yet, with its account, about to be
    /// paid (or re-paid).
    public init?(record: LaundryCheckout, engineGeneration: Int, now: Date) {
        guard record.immediate, record.start == nil, record.phase == .created || record.phase == .paying,
              let orderID = record.orderID, let createdAt = record.createdAt, let accountID = record.accountID
        else { return nil }
        self.orderID = orderID; self.createdAt = createdAt; self.accountID = accountID
        self.engineGeneration = engineGeneration
        self.until = now.addingTimeInterval(Self.maxDuration)
    }

    /// Whether the window's reads go on: the same order, account and engine, inside the window,
    /// waiting for the payment or the start. Ends once the start was tried, the order washes or
    /// ended, or the launch failed.
    public func shouldContinue(_ record: LaundryCheckout?, engineGeneration: Int, now: Date) -> Bool {
        guard let record, record.immediate, now < until, engineGeneration == self.engineGeneration,
              record.orderID == orderID, record.createdAt == createdAt, record.accountID == accountID,
              record.start == nil else { return false }
        if let status = record.order?.status, status.isWashing || status.isTerminal { return false }
        switch record.phase {
        case .paying, .verifying, .active: return true
        case .created: return record.notice == nil
        case .none, .creating, .reconcile, .cancelling, .attention: return false
        }
    }
}
