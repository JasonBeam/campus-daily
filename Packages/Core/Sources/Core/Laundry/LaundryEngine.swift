import Foundation

/// Opens checked payment launches (App: `UIApplication.open` for checkout URLs, AlipaySDK
/// `payOrder` for signed orders). Returns whether Alipay was opened.
public protocol PaymentLauncher: Sendable {
    func open(_ launch: PayLaunch) async -> Bool
}

public enum LaundryEngineError: Error, Equatable, Sendable {
    /// Another operation is running.
    case busy
    /// Not allowed in the current state (e.g. pay without an unpaid order at the confirmed price).
    case notAllowed
    /// Machine/program/price changed or the snapshot is too old: re-read the machine.
    case washerChanged
    /// A checkout write failed: nothing more is sent until relaunch (fail closed).
    case storage
}

/// Drives `LaundryReducer`: persists every state before running its effects, talks to U净
/// through `LaundryOrdering` and opens Alipay through `PaymentLauncher`. Create, payment
/// arguments and cancel are each sent at most once per user confirmation.
public actor LaundryEngine {
    let api: LaundryOrdering
    let vault: LaundryVault
    let launcher: PaymentLauncher
    let accountID: String?
    let inFront: @Sendable () async -> Bool
    let now: @Sendable () -> Date
    let sleep: @Sendable (TimeInterval) async throws -> Void
    /// The TestFlight debug log: phases, request outcomes, U净's status codes, a salted order tag.
    let debugLog: any DebugLogSink

    public private(set) var state: LaundryCheckout
    public private(set) var storageBlocked = false
    private var busy = false
    private let resetMarker: ResetMarker?
    private var observers: [UUID: AsyncStream<LaundryCheckout>.Continuation] = [:]

    /// Restores the persisted record (relaunch rules in `LaundryReducer.restore`).
    /// `resetMarker`: while a reset runs, no order is created (`AppReset.InProgress`).
    /// `accountID`: the signed-in U净 account `api` sends as; a new order records it.
    public init(api: LaundryOrdering, vault: LaundryVault, launcher: PaymentLauncher,
                accountID: String? = nil, resetMarker: ResetMarker? = nil,
                inFront: @escaping @Sendable () async -> Bool = { false }, now: @escaping @Sendable () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { s in
                    try await Task.sleep(nanoseconds: UInt64(max(0, s) * 1_000_000_000))
                }, debugLog: any DebugLogSink = NoDebugLog()) throws {
        self.api = api; self.vault = vault; self.launcher = launcher; self.accountID = accountID
        self.inFront = inFront; self.now = now; self.sleep = sleep; self.debugLog = debugLog
        self.resetMarker = resetMarker
        let persisted: LaundryCheckout?
        do { persisted = try vault.checkout() } catch { throw LaundryEngineError.storage }
        let restored = LaundryReducer.restore(persisted)
        var blocked = false
        if let persisted, restored.persistable != persisted {
            do { try vault.saveCheckout(restored.persistable) } catch { blocked = true }
        }
        self.storageBlocked = blocked
        self.state = restored
    }


    /// Current state first, then every change.
    public func updates() -> AsyncStream<LaundryCheckout> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<LaundryCheckout>.makeStream(bufferingPolicy: .bufferingNewest(16))
        continuation.yield(state)
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    // MARK: User actions

    /// After the confirmation sheet (machine, program, price): create once, then read the order.
    /// `immediate`: 立刻洗衣, the app starts the machine after payment (recorded on the order).
    @discardableResult
    public func confirmOrder(_ snapshot: WasherSnapshot, program: WasherProgram, immediate: Bool = false) async throws -> LaundryCheckout {
        try guardIdle()
        try resetMarker?.checkStart(at: now())
        guard state.canCreate else { throw LaundryEngineError.notAllowed }
        guard let draft = LaundryDraft.make(snapshot, program: program, now: now()) else { throw LaundryEngineError.washerChanged }
        debugLog.record(.laundryStart(.chosen(immediate: immediate)))
        return try await run(.confirm(draft, at: now(), account: accountID, immediate: immediate))
    }

    /// 付款: channel lookup, then payment arguments (once), then open Alipay.
    @discardableResult
    public func pay() async throws -> LaundryCheckout {
        try guardIdle()
        guard state.canPay else { throw LaundryEngineError.notAllowed }
        return try await run(.pay)
    }

    /// First tap of 再付一次 (allowed ≥ 2 min after the last request with a fresh unpaid read).
    @discardableResult
    public func requestRepay() async throws -> LaundryCheckout {
        try guardIdle()
        guard state.canRepay(at: now()) else { throw LaundryEngineError.notAllowed }
        return try await run(.requestRepay(at: now()))
    }

    /// Second confirmation of a re-pay.
    @discardableResult
    public func confirmRepay() async throws -> LaundryCheckout {
        try guardIdle()
        guard state.repayArmed, state.canRepay(at: now()) else { throw LaundryEngineError.notAllowed }
        return try await run(.confirmRepay(at: now()))
    }

    /// The app is back after the Alipay launch (or 10 s after foregrounding): poll the order.
    @discardableResult
    public func returnedFromPayment() async throws -> LaundryCheckout {
        try guardIdle()
        guard state.phase == .paying else { return state }
        await logReturn()
        return try await run(.returnedFromPayment)
    }

    /// Cancel an unpaid (10/17) order: fresh read, one POST, then reads until 53.
    @discardableResult
    public func cancel() async throws -> LaundryCheckout {
        try guardIdle()
        guard state.canCancel else { throw LaundryEngineError.notAllowed }
        return try await run(.cancel)
    }

    /// Pull to refresh / foreground: read the order (reconcile: look for the unfinished order).
    @discardableResult
    public func refresh() async throws -> LaundryCheckout {
        try guardIdle()
        await logReturn()
        return try await run(.refresh)
    }

    /// The user checked a 52 order in the U净 app.
    @discardableResult
    public func acknowledge() async throws -> LaundryCheckout {
        try guardIdle()
        guard state.phase == .attention else { throw LaundryEngineError.notAllowed }
        return try await run(.acknowledge)
    }

    /// Reconcile found nothing and the user checked the U净 app: clear the record.
    @discardableResult
    public func resolveManually() async throws -> LaundryCheckout {
        try guardIdle()
        guard state.canResolveManually else { throw LaundryEngineError.notAllowed }
        return try await run(.resolveManually)
    }

    // MARK: Loop

    private func guardIdle() throws {
        guard !busy else { throw LaundryEngineError.busy }
        guard !storageBlocked else { throw LaundryEngineError.storage }
    }

    private func run(_ first: LaundryEvent) async throws -> LaundryCheckout {
        busy = true
        defer { busy = false }
        var queue = [first]
        while !queue.isEmpty {
            let event = queue.removeFirst()
            let before = state
            let (next, effects) = LaundryReducer.reduce(state, event)
            do { try commit(next) } catch {
                if next.start?.isSent == true, before.start?.isSent != true { debugLog.record(.laundryStart(.skipped(.notSaved))) }
                throw error
            }
            logStart(event, before: before, after: next, effects: effects)
            for effect in effects {
                if let follow = await perform(effect) { queue.append(follow) }
            }
        }
        return state
    }

    /// Persist, then publish. A failed write blocks every later side effect.
    private func commit(_ next: LaundryCheckout) throws {
        let changed = next.persistable != state.persistable
        if next.phase != state.phase || next.lastOutcome?.status != state.lastOutcome?.status {
            debugLog.record(.laundryPhase(from: state.phase, to: next.phase, outcome: next.lastOutcome.map { DebugCode($0.status.code) }))
        }
        state = next
        if changed {
            do { try vault.saveCheckout(next.phase == .none && next.lastOutcome == nil ? nil : next.persistable) }
            catch {
                storageBlocked = true
                publish()
                throw LaundryEngineError.storage
            }
        }
        publish()
    }

    private func publish() {
        for c in observers.values { c.yield(state) }
    }

    private func perform(_ effect: LaundryEffect) async -> LaundryEvent? {
        let event = await performOnce(effect)
        if let event { log(event) }
        return event
    }

    /// 立刻洗衣 coming back to an order not tried yet: whether the app is in front.
    private func logReturn() async {
        guard state.immediate, state.start == nil, state.phase == .paying || state.phase == .active || state.phase == .verifying
        else { return }
        debugLog.record(.laundryStart(.returned(inFront: await inFront())))
    }

    /// 立刻洗衣's start record after a step: stored as sent (the write succeeded), given up for
    /// good, or a pre-start read that did not lead to a start.
    private func logStart(_ event: LaundryEvent, before: LaundryCheckout, after: LaundryCheckout, effects: [LaundryEffect]) {
        guard after.immediate else { return }
        if after.start != before.start {
            if after.start?.isSent == true { debugLog.record(.laundryStart(.saved)) }
            if case .blocked(let reason)? = after.start { debugLog.record(.laundryStart(.skipped(DebugStartSkip(reason)))) }
        }
        guard case .startCheckRead(let check, _) = event, after.start == before.start,
              !effects.contains(where: { if case .startWasher = $0 { return true } else { return false } })
        else { return }
        let reason: DebugStartSkip
        if check.order.id != before.orderID || !LaundryReducer.belongs(check.order, before) { reason = .otherOrder }
        else if check.order.paid != true || check.order.status.code != "20" { reason = .status }
        else { reason = .price }
        debugLog.record(.laundryStart(.skipped(reason)))
    }

    /// One line per answer: which request and how it went (U净's code only), and the order's status.
    private func log(_ event: LaundryEvent) {
        switch event {
        case .created: debugLog.record(.laundryRequest(.create, .ok))
        case .createFailed(let e): debugLog.record(.laundryRequest(.create, DebugOutcome(e)))
        case .orderRead(let order, _):
            debugLog.record(.laundryRequest(.orderDetail, .ok))
            debugLog.record(.laundryOrder(status: DebugCode(order.status.code), moduleType: nil, order: DebugTag(.order, order.id)))
        case .orderReadFailed(let e): debugLog.record(.laundryRequest(.orderDetail, DebugOutcome(e)))
        case .activeOrderFound: debugLog.record(.laundryRequest(.findActive, .ok))
        case .activeOrderLookupFailed(let e): debugLog.record(.laundryRequest(.findActive, DebugOutcome(e)))
        case .paymentMethods: debugLog.record(.laundryRequest(.paymentMethods, .ok))
        case .paymentMethodsFailed(let e): debugLog.record(.laundryRequest(.paymentMethods, DebugOutcome(e)))
        case .paymentArguments: debugLog.record(.laundryRequest(.paymentArguments, .ok))
        case .paymentFailed(let e): debugLog.record(.laundryRequest(.paymentArguments, DebugOutcome(e)))
        case .launched(let opened): debugLog.record(.laundryPayLaunch(opened: opened))
        case .cancelAcknowledged: debugLog.record(.laundryRequest(.cancelOrder, .ok))
        case .cancelFailed(let e): debugLog.record(.laundryRequest(.cancelOrder, DebugOutcome(e)))
        case .startCheckRead(let check, _):
            debugLog.record(.laundryRequest(.startCheck, .ok))
            debugLog.record(.laundryStart(.check(paid: check.order.paid == true, status: DebugCode(check.order.status.code),
                                                 price: DebugPriceCheck(read: check.order.price, confirmed: state.draft?.program.price),
                                                 moduleType: check.moduleType, order: DebugTag(.order, check.order.id))))
        case .startCheckFailed(let e): debugLog.record(.laundryRequest(.startCheck, DebugOutcome(e)))
        case .startSent:
            debugLog.record(.laundryRequest(.startWasher, .ok))
            debugLog.record(.laundryStart(.result(.ok)))
        case .startFailed(let e, _):
            debugLog.record(.laundryRequest(.startWasher, DebugOutcome(e)))
            debugLog.record(.laundryStart(.result(DebugStartResult(e))))
        case .startBlocked: break  // `logStart` writes the reason once it is stored
        default: break
        }
    }

    private func performOnce(_ effect: LaundryEffect) async -> LaundryEvent? {
        switch effect {
        case .create(let request):
            guard !Task.isCancelled else { return .cancelledBeforeSend }
            do { return .created(orderID: try await api.createOrder(request)) }
            catch { return .createFailed(Self.serviceError(error, stateChanging: true)) }

        case .readOrder(let id, let after):
            if after > 0 {
                do { try await sleep(after) } catch { return nil }  // cancelled: stop polling, record kept
            }
            do { return .orderRead(try await api.order(id), at: now()) }
            catch { return .orderReadFailed(Self.serviceError(error, stateChanging: false)) }

        case .findActiveOrder(let qr, let deviceID):
            do {
                let scan = try await api.scan(qr: qr)
                guard scan.deviceID == deviceID else { return .activeOrderLookupFailed(.malformed(.ujing, "data.result.deviceId")) }
                return .activeOrderFound(scan.activeOrderID)
            } catch { return .activeOrderLookupFailed(Self.serviceError(error, stateChanging: false)) }

        case .loadPaymentMethods(let id):
            do { return .paymentMethods(try await api.paymentMethods(id), at: now()) }
            catch { return .paymentMethodsFailed(Self.serviceError(error, stateChanging: false)) }

        case .requestPaymentArguments(let id, let channel):
            guard !Task.isCancelled else { return .cancelledBeforeSend }
            do { return .paymentArguments(try await api.paymentArguments(id, channel: channel)) }
            catch { return .paymentFailed(Self.serviceError(error, stateChanging: true)) }

        case .launch(let launch):
            // Final gate right before opening (the reducer already checked the amount).
            if case .checkout(let url) = launch, !PaymentLaunchPolicy.isAllowedCheckoutURL(url) { return .launched(false) }
            return .launched(await launcher.open(launch))

        case .cancelOrder(let id):
            guard !Task.isCancelled else { return .cancelledBeforeSend }
            do { try await api.cancel(id); return .cancelAcknowledged }
            catch { return .cancelFailed(Self.serviceError(error, stateChanging: true)) }

        case .readStartCheck(let id):
            guard ownsOrder else { return .startBlocked(.account) }
            if let skip = await frontGate() { debugLog.record(.laundryStart(.skipped(skip))); return .startNotNow }
            do { return .startCheckRead(try await api.startCheck(id), at: now()) }
            catch { return .startCheckFailed(Self.serviceError(error, stateChanging: false)) }

        case .startWasher(let id):
            // `start` is stored as sent. Up to the call it may still go back to "not tried";
            // once the request is handed over, every outcome keeps it (never sent twice).
            guard ownsOrder else { return .startBlocked(.account) }
            if let skip = await frontGate() { debugLog.record(.laundryStart(.skipped(skip))); return .startNotNow }
            debugLog.record(.laundryStart(.handed))
            do { try await api.startWasher(id); return .startSent(at: now()) }
            catch { return .startFailed(Self.serviceError(error, stateChanging: true), at: now()) }
        }
    }

    /// Nil when a 立刻洗衣 request may go out now: the task is live and the app is in front.
    private func frontGate() async -> DebugStartSkip? {
        guard !Task.isCancelled else { return .cancelled }
        guard await inFront() else { return .notFront }
        return Task.isCancelled ? .cancelled : nil
    }

    /// The order was placed by the account `api` sends as (立刻洗衣 starts only then).
    private var ownsOrder: Bool {
        guard let owner = state.accountID, let accountID else { return false }
        return owner == accountID
    }

    static func serviceError(_ error: Error, stateChanging: Bool) -> ServiceError {
        if let e = error as? ServiceError { return stateChanging ? e.forStateChangingRequest(.ujing) : e }
        return stateChanging ? .uncertain(.ujing) : .offline
    }
}
