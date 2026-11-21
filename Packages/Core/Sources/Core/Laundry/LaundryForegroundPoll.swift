//
//  LaundryForegroundPoll.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import Foundation

/// When the app reads the open laundry order while it is in front (the scene's polling task).
/// A 立刻洗衣 order that still needs its start is read every second for the first 20 seconds
/// back in front, then every 3 seconds, inside its 10-minute window; any other open order every
/// 30 seconds while the done reminder is on. A read that failed waits 30 seconds whatever the
/// order says next, and a read skipped because another step was running counts for nothing.
///
/// Reading is not free of effects: an order read may lead to the pre-start read and
/// `control/start` under the engine's rules (`LaundryReducer.startIfDue`). This type only says
/// when to read; the engine still decides whether anything is started, and starts it once.
public struct LaundryForegroundPoll: Sendable, Equatable {
    /// How long after coming to the front a start-needing order is read every second.
    public static let fastPeriod: TimeInterval = 20
    public static let fastInterval: TimeInterval = 1
    public static let startInterval: TimeInterval = 3
    public static let regularInterval: TimeInterval = 30
    /// The wait after a failed read, on its own clock.
    public static let failureBackoff: TimeInterval = 30

    /// What the polling task is rebuilt on: the app coming to or leaving the front, the engine
    /// (rebuilt for another U净 account) and the order record. Never the start record, the
    /// pre-start read or a running step: those change in the middle of a read the task itself
    /// runs, and rebuilding it then would cancel that read, a start included.
    public struct Identity: Hashable, Sendable {
        public var inFront: Bool
        public var engine: Int
        /// The confirmation time of the open order (nil: none open). It stays the same from
        /// 下单 to the end, unlike the order id, which arrives during the create.
        public var order: Date?

        public init(inFront: Bool, engine: Int, record: LaundryCheckout?) {
            self.inFront = inFront
            self.engine = engine
            let open = (record?.phase ?? LaundryPhase.none) != LaundryPhase.none
            order = open ? (record?.createdAt ?? Date.distantPast) : nil
        }
    }

    /// How one read the task asked for went.
    public enum Outcome: Sendable, Equatable {
        /// U净 answered.
        case read
        /// The read failed (U净 unreachable or refusing, the login gone, a reply about another
        /// order, the record not writable).
        case failed
        /// Nothing was read: another step was running, or there was nothing to read.
        case skipped

        /// From the notice the read left on the record.
        public init(notice: LaundryNotice?) {
            switch notice {
            case .readFailed?, .refused?, .sessionExpired?, .orderMismatch?: self = .failed
            default: self = .read
            }
        }

        /// From the error the read threw: busy is a skip, anything else a failure.
        public init(error: Error) {
            self = (error as? LaundryEngineError) == .busy ? .skipped : .failed
        }
    }

    /// When the app came to the front (the start of this task).
    public let frontSince: Date
    /// The last read that was made (failed or not).
    public private(set) var lastRead: Date?
    /// The last failed read, until a read goes through.
    public private(set) var failedAt: Date?

    public init(frontSince: Date) { self.frontSince = frontSince }

    /// A 立刻洗衣 order paid or being checked, no start tried yet, not washing, inside its window.
    public static func needsStart(_ c: LaundryCheckout?, now: Date) -> Bool {
        guard let c, c.immediate, c.start == nil, c.inStartWindow(at: now) else { return false }
        switch c.phase {
        case .verifying: return true
        case .active: return c.order?.status.isWashing != true
        default: return false
        }
    }

    /// An order the done reminder follows: unpaid, being checked or paid.
    public static func inProgress(_ c: LaundryCheckout?) -> Bool {
        guard let c else { return false }
        return [.created, .verifying, .active].contains(c.phase)
    }

    /// Seconds between reads for `c` now, or nil when it isn't read on a timer.
    public func interval(_ c: LaundryCheckout?, remindersOn: Bool, now: Date) -> TimeInterval? {
        if Self.needsStart(c, now: now) {
            return now.timeIntervalSince(frontSince) < Self.fastPeriod ? Self.fastInterval : Self.startInterval
        }
        if remindersOn, Self.inProgress(c) { return Self.regularInterval }
        return nil
    }

    /// Whether to read now. The first start-needing read is at once; the first reminder read
    /// waits an interval (coming to the front reads the order anyway).
    public func isDue(_ c: LaundryCheckout?, remindersOn: Bool, now: Date) -> Bool {
        guard let interval = interval(c, remindersOn: remindersOn, now: now) else { return false }
        if let failedAt, now.timeIntervalSince(failedAt) < Self.failureBackoff { return false }
        let last = lastRead ?? (Self.needsStart(c, now: now) ? nil : frontSince)
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    public mutating func record(_ outcome: Outcome, at: Date) {
        switch outcome {
        case .read: lastRead = at; failedAt = nil
        case .failed: lastRead = at; failedAt = at
        case .skipped: break
        }
    }
}
