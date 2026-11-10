import Foundation

// 立刻洗衣: after the user paid, the app asks U净 once to start the machine (`control/start`),
// only for an order the user chose it for, only while the app is in front, and never twice.

/// Why the app won't start this order itself (the user starts it in the U净 app).
public enum LaundryStartBlock: String, Sendable, Codable, Equatable {
    /// Not module type 7.
    case unsupported
    /// U净 says the machine is offline.
    case offline
    /// The machine wants a paid self-clean first.
    case selfClean
    /// A detergent-dispenser order (`wp_order`): U净 prepares it first.
    case dispenser
    /// More than `LaundryCheckout.startWindow` after the order was confirmed.
    case expired
    /// The signed-in U净 account is not the one that placed the order.
    case account
    /// The pre-start read's price is above the confirmed one, missing or zero (in fen).
    case price
}

/// The order's start attempt. Once anything but nil is stored, `control/start` is never sent
/// again for this order (only `sent` can go back to nil, and only before the request left).
public enum LaundryStart: Sendable, Codable, Equatable {
    /// Stored right before `control/start` is handed to the network.
    case sent(at: Date)
    /// U净 took it; waiting for the machine.
    case accepted(at: Date)
    /// No clear answer (timeout, lost connection, unreadable reply).
    case pending(at: Date)
    /// U净 said no, in its own words (may be empty).
    case refused(message: String, at: Date)
    /// Never tried, and never will be.
    case blocked(LaundryStartBlock)
    /// A washing read came after the request.
    case started

    /// Stored as sent, the request not answered yet.
    public var isSent: Bool { if case .sent = self { return true } else { return false } }

    /// When the request was made (nil: never made, or washing already).
    public var requestedAt: Date? {
        switch self {
        case .sent(let at), .accepted(let at), .pending(let at), .refused(_, let at): return at
        case .blocked, .started: return nil
        }
    }
}

/// The order card's 立刻洗衣 line. Only for 立刻洗衣 orders.
public struct LaundryStartLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Chosen, not paid yet.
        case armed
        /// Paid, about to be checked.
        case ready
        /// The pre-start read is running.
        case checking
        /// The start request went out.
        case sent
        /// No clear answer.
        case uncertain
        /// Left to the U净 app.
        case blocked
        /// U净 said no.
        case refused
    }
    public var kind: Kind
    public var text: String
    public var detail: String?
    public init(kind: Kind, text: String, detail: String? = nil) { self.kind = kind; self.text = text; self.detail = detail }

    /// Shown in the notice colour (the user has something to do in the U净 app).
    public var isNotice: Bool { [.uncertain, .blocked, .refused].contains(kind) }
}

extension LaundryCheckout {
    /// A paid (20) 立刻洗衣 order never tried: the next read is the pre-start read.
    var wantsStartCheck: Bool {
        guard immediate, start == nil, phase == .active, let order else { return false }
        return order.status.code == "20" && order.paid == true
    }

    /// Within `startWindow` of the confirmation (an unknown or future time is outside).
    func inStartWindow(at now: Date) -> Bool {
        guard let createdAt else { return false }
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age <= Self.startWindow
    }
}

extension LaundryReducer {
    /// After a paid read: ask for the pre-start read, or give up for good once the window is over.
    static func startIfDue(_ state: LaundryCheckout, at: Date) -> (LaundryCheckout, [LaundryEffect]) {
        var s = state
        guard s.wantsStartCheck, let id = s.orderID else { return (s, []) }
        guard s.inStartWindow(at: at) else {
            s.start = .blocked(.expired)
            return (s, [])
        }
        s.checkingStart = true
        return (s, [.readStartCheck(id: id)])
    }

    /// The pre-start read: start only for this order, paid, 20, at no more than the confirmed
    /// price (in fen), inside the window, on a machine the app may start.
    static func startCheckRead(_ check: LaundryStartCheck, at: Date, state: LaundryCheckout) -> (LaundryCheckout, [LaundryEffect]) {
        var s = state
        guard check.order.id == state.orderID, belongs(check.order, state) else {
            s.notice = .orderMismatch
            return (s, [])
        }
        var (n, effects) = apply(check.order, at: at, to: s, checkStart: false)
        guard n.wantsStartCheck, let id = n.orderID else { return (n, effects) }
        guard n.inStartWindow(at: at) else {
            n.start = .blocked(.expired)
            return (n, effects)
        }
        guard let price = check.order.price?.fen, let confirmed = n.draft?.program.price.fen,
              price > 0, price <= confirmed else {
            // Never started, never looked at again (no notice: `.priceChanged` speaks of payment).
            n.start = .blocked(.price)
            return (n, effects)
        }
        if let block = check.block {
            n.start = .blocked(block)
            return (n, effects)
        }
        n.start = .sent(at: at)
        effects.append(.startWasher(id: id))
        return (n, effects)
    }

    /// After the start reply (whatever it was): read the order on the payment poll's steps.
    static func startPoll(_ state: LaundryCheckout) -> (LaundryCheckout, [LaundryEffect]) {
        var s = state
        guard let id = s.orderID else { return (s, []) }
        s.startPollAttempt = 0
        return (s, [.readOrder(id: id, after: LaundryCheckout.pollDelays[0])])
    }

    /// The next read of the post-start poll, until washing, a phase change or the last step.
    static func continueStartPoll(_ state: LaundryCheckout, _ effects: [LaundryEffect]) -> (LaundryCheckout, [LaundryEffect]) {
        var s = state
        guard let attempt = state.startPollAttempt else { return (s, effects) }
        guard s.phase == .active, s.order?.status.isWashing != true, let id = s.orderID else {
            s.startPollAttempt = nil
            return (s, effects)
        }
        let next = attempt + 1
        guard next < LaundryCheckout.pollDelays.count else {
            s.startPollAttempt = nil
            return (s, effects)
        }
        s.startPollAttempt = next
        return (s, effects + [.readOrder(id: id, after: LaundryCheckout.pollDelays[next])])
    }
}

extension LaundryStartLine {
    /// The line for `c`, nil for normal orders and once washing.
    public static func make(_ c: LaundryCheckout) -> LaundryStartLine? {
        guard c.immediate else { return nil }
        switch c.phase {
        case .created, .paying, .verifying:
            return LaundryStartLine(kind: .armed, text: "付完款回到这里，就帮你启动机器。")
        case .active:
            break
        default:
            return nil
        }
        if c.order?.status.isWashing == true { return nil }
        if c.checkingStart { return LaundryStartLine(kind: .checking, text: "正在核对机器…") }
        switch c.start {
        case nil:
            return LaundryStartLine(kind: .ready, text: "已付款，马上帮你启动。")
        case .sent?, .accepted?:
            return LaundryStartLine(kind: .sent, text: "启动指令发出去了，等机器响应。")
        case .pending?:
            return LaundryStartLine(kind: .uncertain, text: "不确定机器启动了没有。", detail: "别再启动，去 U净 App 里看看。")
        case .refused(let message, _)?:
            let words = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return LaundryStartLine(kind: .refused, text: words.isEmpty ? "U净 没让启动。" : "U净 没让启动：\(words)",
                                    detail: "去 U净 App 里启动。")
        case .blocked(.expired)?:
            return LaundryStartLine(kind: .blocked, text: "下单超过 10 分钟，没帮你启动。", detail: "去 U净 App 里启动。")
        case .blocked(.account)?:
            return LaundryStartLine(kind: .blocked, text: "这单是另一个 U净 账号下的，没帮你启动。", detail: "去那个账号的 U净 App 里启动。")
        case .blocked(.price)?:
            return LaundryStartLine(kind: .blocked, text: "这单的价格对不上，没帮你启动。", detail: "去 U净 App 里启动。")
        case .blocked?:
            return LaundryStartLine(kind: .blocked, text: "这台机器要在 U净 App 里启动。")
        case .started?:
            return nil
        }
    }
}
