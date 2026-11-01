import Foundation

// Laundry order state machine (architecture §3.2). Pure: `LaundryEngine` persists the state a
// transition returns *before* running its effects, so create / pay / cancel are each guarded
// by a stored "this may have happened" record. Nothing that can cost money is retried
// automatically.

public enum LaundryPhase: String, Sendable, Codable, CaseIterable {
    /// No order in progress.
    case none
    /// Persisted right before `orders/create` leaves.
    case creating
    /// Create outcome unknown: look for the account's unfinished order, never create again.
    case reconcile
    /// Order exists (normally unpaid).
    case created
    /// Persisted right before `payment/arguments`; then the Alipay app is opened.
    case paying
    /// Back from Alipay (or no launch needed): polling the order.
    case verifying
    /// Paid: waiting to start / starting / washing.
    case active
    /// Cancel requested (pre-check read, then one POST, then reads).
    case cancelling
    /// Order 52 (machine didn't start): kept until the user acknowledges it.
    case attention
}

/// The machine + program the user confirmed.
public struct LaundryDraft: Sendable, Equatable, Codable {
    public var deviceID: String
    public var qrCode: String
    /// `deviceNo` for display.
    public var machineName: String
    public var program: WasherProgram
    public var request: OrderRequest
    public init(deviceID: String, qrCode: String, machineName: String, program: WasherProgram, request: OrderRequest) {
        self.deviceID = deviceID; self.qrCode = qrCode; self.machineName = machineName; self.program = program; self.request = request
    }

    /// Builds the draft from a fresh, orderable snapshot whose program list still contains
    /// `program` at the same price. Nil = re-read the machine ("机器或价格变了").
    public static func make(_ s: WasherSnapshot, program: WasherProgram, now: Date) -> LaundryDraft? {
        let age = now.timeIntervalSince(s.fetchedAt)
        guard s.isOrderable, age >= 0, age < WasherSnapshot.maxOrderAge,
              s.info.deviceID == s.scan.deviceID,
              let listed = s.info.programs.first(where: { $0.id == program.id }), listed == program,
              let store = s.info.storeID, let type = s.info.deviceTypeID else { return nil }
        return LaundryDraft(deviceID: s.deviceID, qrCode: s.qrCode, machineName: s.info.deviceNo, program: program,
                            request: OrderRequest(deviceID: s.deviceID, deviceTypeID: type, storeID: store, programID: program.id))
    }
}

/// The last finished order (shown for a while after the record is cleared).
public struct LaundryOutcome: Sendable, Equatable, Codable {
    public var orderID: String
    public var status: LaundryOrderStatus
    public var at: Date
    public init(orderID: String, status: LaundryOrderStatus, at: Date) { self.orderID = orderID; self.status = status; self.at = at }
}

/// Shown once; the phase itself is unchanged unless the transition says otherwise.
public enum LaundryNotice: Sendable, Codable, Equatable {
    /// U净 said no (create/pay/cancel/read), in its own words.
    case refused(ServiceError)
    /// A read failed; the record is kept.
    case readFailed(ServiceError)
    /// The login is gone: sign in again, the record is kept.
    case sessionExpired
    /// Machine or price changed before create: re-read.
    case washerChanged
    /// U净's order amount is above the confirmed price: payment blocked.
    case priceChanged
    /// The order read back is not ours (other machine/program/id).
    case orderMismatch
    /// Reconcile found no unfinished order on this machine.
    case orderNotFound
    /// No usable Alipay channel for this order.
    case noPayChannel
    /// The payment reply failed the launch check: nothing opened.
    case launchRefused(PaymentLaunchRefusal)
    /// The Alipay app did not open.
    case launchFailed
    /// Polling ended with the order still unpaid.
    case paymentNotConfirmed
    /// Polling ended without seeing the cancellation.
    case cancelUnconfirmed
    /// The order is already paid/running: cancel not possible.
    case cancelNotAllowed
}

/// Live Activity / done-notification plan for a washing order (status 40).
public struct LaundryActivityPlan: Sendable, Equatable, Codable {
    public var orderID: String
    public var machineName: String
    public var programName: String
    public var endsAt: Date?
    public init(orderID: String, machineName: String, programName: String, endsAt: Date?) {
        self.orderID = orderID; self.machineName = machineName; self.programName = programName; self.endsAt = endsAt
    }
}

/// Keychain `laundry.checkout` (one record at a time).
public struct LaundryCheckout: Sendable, Equatable, Codable {
    public var phase: LaundryPhase
    public var draft: LaundryDraft?
    /// Local time the create was confirmed.
    public var createdAt: Date?
    public var orderID: String?
    public var order: LaundryOrder?
    public var orderReadAt: Date?
    /// Reconcile: the unfinished order U净 reported for this machine, being checked.
    public var candidateOrderID: String?
    /// Set (and persisted) right before `payment/arguments` leaves.
    public var paymentRequestedAt: Date?
    /// First tap of a re-pay; the second confirmation requests payment again.
    public var repayArmed: Bool
    /// Persisted right before `orders/{id}/cancel` leaves.
    public var cancelSent: Bool
    /// Polling step in `verifying` / `cancelling`.
    public var pollAttempt: Int
    public var lastOutcome: LaundryOutcome?
    public var notice: LaundryNotice?

    public init(phase: LaundryPhase = .none, draft: LaundryDraft? = nil, createdAt: Date? = nil, orderID: String? = nil,
                order: LaundryOrder? = nil, orderReadAt: Date? = nil, candidateOrderID: String? = nil,
                paymentRequestedAt: Date? = nil, repayArmed: Bool = false, cancelSent: Bool = false, pollAttempt: Int = 0,
                lastOutcome: LaundryOutcome? = nil, notice: LaundryNotice? = nil) {
        self.phase = phase; self.draft = draft; self.createdAt = createdAt; self.orderID = orderID; self.order = order
        self.orderReadAt = orderReadAt; self.candidateOrderID = candidateOrderID; self.paymentRequestedAt = paymentRequestedAt
        self.repayArmed = repayArmed; self.cancelSent = cancelSent; self.pollAttempt = pollAttempt
        self.lastOutcome = lastOutcome; self.notice = notice
    }

    public static let empty = LaundryCheckout()

    /// Poll delays (seconds) after returning from Alipay / after a cancel: ≈ 1 minute in total.
    public static let pollDelays: [TimeInterval] = [2, 4, 8, 15, 15, 15]
    /// No re-pay within this many seconds of the last payment request.
    public static let repayWindow: TimeInterval = 120
    /// A re-pay needs an unpaid read at most this old.
    public static let repayReadMaxAge: TimeInterval = 300
    /// Reconcile adopts an order created within this many seconds of our confirmation.
    public static let adoptWindow: TimeInterval = 120

    /// A new order may be confirmed.
    public var canCreate: Bool { phase == .none }

    /// The order price is known and not above what the user confirmed.
    public var priceAccepted: Bool {
        guard let price = order?.price, let confirmed = draft?.program.price else { return false }
        return price.fen > 0 && price <= confirmed
    }

    /// First payment of an unpaid order.
    public var canPay: Bool {
        phase == .created && order?.isUnpaid == true && priceAccepted && paymentRequestedAt == nil
    }

    /// Paying again: unpaid at the confirmed price, the last request ≥ 2 min ago, and a read
    /// taken after that window that is still recent.
    public func canRepay(at now: Date) -> Bool {
        guard phase == .created, order?.isUnpaid == true, priceAccepted,
              let requested = paymentRequestedAt, let read = orderReadAt else { return false }
        return now.timeIntervalSince(requested) >= Self.repayWindow
            && read.timeIntervalSince(requested) >= Self.repayWindow
            && now.timeIntervalSince(read) >= 0 && now.timeIntervalSince(read) < Self.repayReadMaxAge
    }

    /// Cancel only an unpaid 10/17 order.
    public var canCancel: Bool { phase == .created && order?.isUnpaid == true }

    /// `reconcile` can be cleared by the user after checking the U净 app.
    public var canResolveManually: Bool { phase == .reconcile }

    /// What goes to the Keychain (no one-shot notice / arming).
    public var persistable: LaundryCheckout {
        var c = self
        c.notice = nil
        c.repayArmed = false
        return c
    }

    func cleared(outcome: LaundryOutcome?) -> LaundryCheckout {
        LaundryCheckout(lastOutcome: outcome ?? lastOutcome)
    }
}

public enum LaundryEvent: Sendable, Equatable {
    /// The user confirmed machine, program and price.
    case confirm(LaundryDraft, at: Date)
    case created(orderID: String)
    case createFailed(ServiceError)
    /// `scanWasherCode` during reconcile: the account's unfinished order on the machine.
    case activeOrderFound(String?)
    case activeOrderLookupFailed(ServiceError)
    case orderRead(LaundryOrder, at: Date)
    case orderReadFailed(ServiceError)
    /// 付款 (first payment, confirmed in the sheet).
    case pay
    case requestRepay(at: Date)
    case confirmRepay(at: Date)
    case paymentMethods([PayChannel], at: Date)
    case paymentMethodsFailed(ServiceError)
    case paymentArguments(PaymentArguments)
    case paymentFailed(ServiceError)
    /// The launcher reported whether Alipay opened.
    case launched(Bool)
    /// The app came back to the foreground after the Alipay launch.
    case returnedFromPayment
    case cancel
    case cancelAcknowledged
    case cancelFailed(ServiceError)
    /// Pull to refresh / app foreground.
    case refresh
    /// A guarded request was cancelled after its record was persisted but before it left.
    case cancelledBeforeSend
    case acknowledge
    case resolveManually
}

public enum LaundryEffect: Sendable, Equatable {
    case create(OrderRequest)
    /// Read the order after `after` seconds → `.orderRead`/`.orderReadFailed`.
    case readOrder(id: String, after: TimeInterval)
    /// `scanWasherCode` → `.activeOrderFound`/`.activeOrderLookupFailed`.
    case findActiveOrder(qrCode: String, deviceID: String)
    case loadPaymentMethods(orderID: String)
    case requestPaymentArguments(orderID: String, channel: PayChannel)
    /// Open Alipay (checked launch) → `.launched`.
    case launch(PayLaunch)
    case cancelOrder(id: String)
    case updateActivity(LaundryActivityPlan)
    case endActivity
    case diagnostic(String)
}

public enum LaundryReducer {
    public static func isDefiniteRefusal(_ e: ServiceError) -> Bool {
        switch e {
        case .rejected, .badRequest, .sessionExpired: return true
        default: return false
        }
    }

    static func notice(for e: ServiceError, read: Bool) -> LaundryNotice {
        if e.isSessionExpired { return .sessionExpired }
        if case .rejected = e { return .refused(e) }
        return read ? .readFailed(e) : .refused(e)
    }

    public static func reduce(_ state: LaundryCheckout, _ event: LaundryEvent) -> (LaundryCheckout, [LaundryEffect]) {
        var s = state
        s.notice = nil
        switch (state.phase, event) {

        // MARK: create
        case (.none, .confirm(let draft, let at)):
            let n = LaundryCheckout(phase: .creating, draft: draft, createdAt: at, lastOutcome: state.lastOutcome)
            return (n, [.create(draft.request)])

        case (.creating, .created(let id)):
            guard UjingInput.isOrderID(id) else {
                s.phase = .reconcile
                return (s, [.diagnostic("create.badOrderId")] + findActive(s))
            }
            s.phase = .created
            s.orderID = id
            return (s, [.readOrder(id: id, after: 0)])

        case (.creating, .createFailed(let e)):
            if isDefiniteRefusal(e) {
                var n = state.cleared(outcome: nil)
                n.notice = notice(for: e, read: false)
                return (n, [])
            }
            s.phase = .reconcile
            return (s, findActive(s))

        case (.creating, .cancelledBeforeSend):
            return (state.cleared(outcome: nil), [])

        // MARK: reconcile
        case (.reconcile, .refresh):
            return (s, findActive(s))

        case (.reconcile, .activeOrderFound(let id)):
            guard let id, UjingInput.isOrderID(id) else {
                s.notice = .orderNotFound
                return (s, [])
            }
            s.candidateOrderID = id
            return (s, [.readOrder(id: id, after: 0)])

        case (.reconcile, .activeOrderLookupFailed(let e)), (.reconcile, .orderReadFailed(let e)):
            s.notice = notice(for: e, read: true)
            return (s, [])

        case (.reconcile, .orderRead(let order, let at)):
            guard let candidate = state.candidateOrderID, order.id == candidate, belongs(order, state),
                  adoptable(order, state) else {
                s.candidateOrderID = nil
                s.notice = .orderMismatch
                return (s, [])
            }
            s.orderID = candidate
            s.candidateOrderID = nil
            s.phase = .created
            return apply(order, at: at, to: s)

        case (.reconcile, .resolveManually):
            return (state.cleared(outcome: nil), [.diagnostic("laundry.resolvedManually")])

        // MARK: reads in order phases
        case (.created, .orderRead(let order, let at)), (.active, .orderRead(let order, let at)),
             (.verifying, .orderRead(let order, let at)), (.cancelling, .orderRead(let order, let at)):
            guard order.id == state.orderID, belongs(order, state) else {
                s.notice = .orderMismatch
                return (s, [])
            }
            return apply(order, at: at, to: s)

        case (.created, .orderReadFailed(let e)), (.active, .orderReadFailed(let e)):
            s.notice = notice(for: e, read: true)
            return (s, [])

        case (.verifying, .orderReadFailed(let e)), (.cancelling, .orderReadFailed(let e)):
            if e.isSessionExpired {
                s.notice = .sessionExpired
                return (s, [])
            }
            if state.phase == .cancelling && !state.cancelSent {
                s.phase = .created
                s.notice = notice(for: e, read: true)
                return (s, [])
            }
            return poll(s, exhausted: state.phase == .verifying ? .paymentNotConfirmed : .cancelUnconfirmed)

        case (.created, .refresh), (.active, .refresh):
            guard let id = state.orderID else { return (state, []) }
            return (s, [.readOrder(id: id, after: 0)])

        case (.verifying, .refresh), (.cancelling, .refresh):
            guard let id = state.orderID, state.phase == .verifying || state.cancelSent else { return (state, []) }
            s.pollAttempt = 0
            return (s, [.readOrder(id: id, after: 0)])

        // MARK: pay
        case (.created, .pay) where state.canPay:
            guard let id = state.orderID else { return (state, []) }
            return (s, [.loadPaymentMethods(orderID: id)])

        case (.created, .requestRepay(let at)) where state.canRepay(at: at):
            s.repayArmed = true
            return (s, [])

        case (.created, .confirmRepay(let at)) where state.repayArmed && state.canRepay(at: at):
            guard let id = state.orderID else { return (state, []) }
            return (s, [.diagnostic("pay.repay"), .loadPaymentMethods(orderID: id)])

        case (.created, .paymentMethods(let channels, let at)) where state.canPay || (state.repayArmed && state.canRepay(at: at)):
            guard let id = state.orderID else { return (state, []) }
            s.repayArmed = false
            guard let channel = PayChannel.preferred(channels) else {
                s.notice = .noPayChannel
                return (s, [])
            }
            s.phase = .paying
            s.paymentRequestedAt = at
            return (s, [.requestPaymentArguments(orderID: id, channel: channel)])

        case (.created, .paymentMethodsFailed(let e)):
            s.repayArmed = false
            s.notice = notice(for: e, read: true)
            return (s, [])

        case (.paying, .paymentArguments(let args)):
            do {
                let launch = try PaymentLaunchPolicy.launch(for: args, orderAmount: state.order?.price)
                if launch == .query { return verify(s) }
                return (s, [.launch(launch)])
            } catch {
                let refusal = (error as? PaymentLaunchRefusal) ?? .unavailable
                s.phase = .created
                s.notice = .launchRefused(refusal)
                return (s, [.diagnostic("pay.launchRefused.\(refusal.rawValue)")])
            }

        case (.paying, .paymentFailed(let e)):
            if isDefiniteRefusal(e) {
                s.phase = .created
                s.notice = notice(for: e, read: false)
                return (s, [])
            }
            // May have been charged (skipPay paths): read the order.
            return verify(s)

        case (.paying, .cancelledBeforeSend):
            // The arguments request never left: nothing requested.
            s.phase = .created
            s.paymentRequestedAt = nil
            return (s, [])

        case (.paying, .launched(let opened)):
            if opened { return (s, []) }
            s.phase = .created
            s.notice = .launchFailed
            return (s, [])

        case (.paying, .returnedFromPayment), (.paying, .refresh):
            return verify(s)

        // MARK: cancel
        case (.created, .cancel) where state.canCancel:
            guard let id = state.orderID else { return (state, []) }
            s.phase = .cancelling
            s.cancelSent = false
            s.pollAttempt = 0
            // Fresh read first; the POST goes only if it is still unpaid.
            return (s, [.readOrder(id: id, after: 0)])

        case (.cancelling, .cancelAcknowledged):
            guard let id = state.orderID else { return (state, []) }
            s.pollAttempt = 0
            return (s, [.readOrder(id: id, after: 0)])

        case (.cancelling, .cancelFailed(let e)):
            if isDefiniteRefusal(e) {
                s.phase = .created
                s.cancelSent = false
                s.notice = notice(for: e, read: false)
                return (s, [])
            }
            guard let id = state.orderID else { return (state, []) }
            s.pollAttempt = 0
            return (s, [.readOrder(id: id, after: LaundryCheckout.pollDelays[0])])

        case (.cancelling, .cancelledBeforeSend) where state.cancelSent:
            s.phase = .created
            s.cancelSent = false
            return (s, [])

        // MARK: leaving
        case (.attention, .acknowledge):
            return (state.cleared(outcome: state.orderID.flatMap { id in state.order.map { LaundryOutcome(orderID: id, status: $0.status, at: state.orderReadAt ?? Date.distantPast) } }), [])

        default:
            return (state, [])
        }
    }

    /// Relaunch: what a persisted record means now. Nothing is re-sent automatically.
    public static func restore(_ persisted: LaundryCheckout?) -> LaundryCheckout {
        guard var s = persisted else { return .empty }
        s.notice = nil
        s.repayArmed = false
        switch s.phase {
        case .none, .reconcile, .created, .active, .attention, .verifying:
            return s
        case .creating:
            // The create may have reached U净.
            s.phase = .reconcile
            return s
        case .paying:
            // Arguments requested; Alipay may have been used.
            s.phase = .verifying
            s.pollAttempt = 0
            return s
        case .cancelling:
            if !s.cancelSent { s.phase = .created }
            return s
        }
    }

    // MARK: helpers

    static func findActive(_ s: LaundryCheckout) -> [LaundryEffect] {
        guard let d = s.draft else { return [] }
        return [.findActiveOrder(qrCode: d.qrCode, deviceID: d.deviceID)]
    }

    static func belongs(_ order: LaundryOrder, _ s: LaundryCheckout) -> Bool {
        guard let d = s.draft else { return false }
        return order.deviceID == d.deviceID && order.programID == d.program.id
    }

    /// Reconcile adopts only an order created around our confirmation at no more than the confirmed price.
    static func adoptable(_ order: LaundryOrder, _ s: LaundryCheckout) -> Bool {
        guard let created = order.createdAt.flatMap(parseDate), let local = s.createdAt,
              abs(created.timeIntervalSince(local)) < LaundryCheckout.adoptWindow else { return false }
        if let price = order.price, let confirmed = s.draft?.program.price, price > confirmed { return false }
        return true
    }

    static func parseDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text)
    }

    static func verify(_ state: LaundryCheckout) -> (LaundryCheckout, [LaundryEffect]) {
        var s = state
        guard let id = s.orderID else { return (s, []) }
        s.phase = .verifying
        s.pollAttempt = 0
        return (s, [.readOrder(id: id, after: LaundryCheckout.pollDelays[0])])
    }

    /// Next poll step, or stop with `exhausted` (verifying → back to created).
    static func poll(_ state: LaundryCheckout, exhausted: LaundryNotice) -> (LaundryCheckout, [LaundryEffect]) {
        var s = state
        guard let id = s.orderID else { return (s, []) }
        s.pollAttempt += 1
        if s.pollAttempt < LaundryCheckout.pollDelays.count {
            return (s, [.readOrder(id: id, after: LaundryCheckout.pollDelays[s.pollAttempt])])
        }
        if s.phase == .verifying { s.phase = .created }
        s.notice = exhausted
        return (s, [])
    }

    /// Applies a matching order read to the current phase.
    static func apply(_ order: LaundryOrder, at: Date, to state: LaundryCheckout) -> (LaundryCheckout, [LaundryEffect]) {
        var s = state
        s.order = order
        s.orderReadAt = at
        let id = s.orderID ?? order.id

        if order.status.isTerminal {
            if order.status.isFailedStart {
                s.phase = .attention
                s.cancelSent = false
                return (s, [.endActivity])
            }
            return (s.cleared(outcome: LaundryOutcome(orderID: id, status: order.status, at: at)), [.endActivity])
        }

        if !order.isUnpaid {
            // Paid / starting / washing (or a status we don't know: no pay, no cancel).
            let wasCancelling = s.phase == .cancelling
            s.phase = .active
            s.cancelSent = false
            if wasCancelling { s.notice = .cancelNotAllowed }
            guard order.status.isWashing, let d = s.draft else { return (s, []) }
            let ends = order.remainSeconds.flatMap { $0 > 0 ? at.addingTimeInterval(TimeInterval($0)) : nil }
            return (s, [.updateActivity(LaundryActivityPlan(orderID: id, machineName: d.machineName,
                                                            programName: d.program.name, endsAt: ends))])
        }

        // Unpaid (10/17).
        switch s.phase {
        case .verifying:
            return poll(s, exhausted: .paymentNotConfirmed)
        case .cancelling:
            if !s.cancelSent {
                s.cancelSent = true
                return (s, [.cancelOrder(id: id)])
            }
            return poll(s, exhausted: .cancelUnconfirmed)
        default:
            s.phase = .created
            if let price = order.price, let confirmed = s.draft?.program.price, price > confirmed { s.notice = .priceChanged }
            return (s, [])
        }
    }
}

// MARK: - Presentation

public struct LaundryDisplay: Sendable, Equatable {
    public var title: String
    public var hint: String?
    public init(_ c: LaundryCheckout) {
        hint = nil
        switch c.phase {
        case .none: title = "空闲"
        case .creating: title = "正在下单…"
        case .reconcile: title = "核对中"; hint = "还没确认订单结果。先刷新核对，别重复下单或付款。"
        case .created: title = c.order?.status.label ?? "已预约"
            if c.notice == .priceChanged { hint = "价格变了，刷新一下" }
        case .paying: title = "正在打开支付宝…"
        case .verifying: title = "正在核对付款…"
        case .active: title = c.order?.status.label ?? "已付款"
        case .cancelling: title = "正在取消…"
        case .attention: title = "机器没启动"; hint = "去 U净 的订单里看看有没有扣款。"
        }
    }
}
