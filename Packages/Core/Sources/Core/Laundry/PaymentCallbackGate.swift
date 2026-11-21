//
//  PaymentCallbackGate.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import Foundation

/// One Alipay payment attempt at a time (`AlipayBridge`). Each `pay` or checkout link begins a
/// new attempt under a new id; the SDK callbacks made for it carry that id, and anything for an
/// attempt that is no longer the current one is dropped. A callback is only a reason to read the
/// order: it never says the order was paid.
///
/// A signed order goes to the SDK (`takenOver`). A checkout link is `pending` until the SDK's
/// interceptor says whether it took it: the first callback before that waits, and goes out on a
/// takeover or is dropped on a decline. Each attempt delivers at most one callback.
public struct PaymentCallbackGate: Sendable {
    public enum State: Sendable, Equatable {
        case pending, takenOver, declined, delivered
    }

    public enum Receipt: Sendable, Equatable {
        /// Ask for the order read now.
        case deliver
        /// Kept until the interceptor decides.
        case buffered
        /// The current attempt's, but declined or already delivered (or a second early one).
        case droppedLate
        /// Another attempt's, or none at all.
        case droppedStale
    }

    public private(set) var current: UUID?
    public private(set) var state: State?
    private var buffered = false

    public init() {}

    /// Supersedes the previous attempt.
    public mutating func begin(id: UUID = UUID(), takenOver: Bool) -> UUID {
        current = id
        state = takenOver ? .takenOver : .pending
        buffered = false
        return id
    }

    public mutating func receive(_ id: UUID) -> Receipt {
        guard id == current, let state else { return .droppedStale }
        switch state {
        case .pending:
            if buffered { return .droppedLate }
            buffered = true
            return .buffered
        case .takenOver:
            self.state = .delivered
            return .deliver
        case .declined, .delivered:
            return .droppedLate
        }
    }

    /// The interceptor's answer for `id`. True when a buffered callback goes out now.
    public mutating func resolve(_ id: UUID, takenOver: Bool) -> Bool {
        guard id == current, state == .pending else { return false }
        defer { buffered = false }
        guard takenOver else { state = .declined; return false }
        if buffered { state = .delivered; return true }
        state = .takenOver
        return false
    }

    /// A `safepay` return URL can't say which attempt it belongs to: it goes to the SDK only
    /// while the current attempt is the SDK's, and never counts as that attempt's callback.
    public var acceptsReturnURL: Bool { state == .takenOver || state == .delivered }
}
