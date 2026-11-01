import Foundation

/// Opens checked payment launches (App: `UIApplication.open` for checkout URLs, AlipaySDK
/// `payOrder` for signed orders). Returns whether Alipay was opened.
public protocol PaymentLauncher: Sendable {
    func open(_ launch: PayLaunch) async -> Bool
}

/// Live Activity / notification / diagnostics hooks (App side). Optional.
public protocol LaundryHooks: Sendable {
    /// Status 40: start or update the Live Activity and schedule the done notification at `endsAt`.
    func updateActivity(_ plan: LaundryActivityPlan) async
    /// 50/51/52/53: end the activity, drop the pending done notification.
    func endActivity() async
    /// Event names only (no ids, links or tokens).
    func diagnostic(_ event: String) async
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
    let hooks: LaundryHooks?
    let now: @Sendable () -> Date
    let sleep: @Sendable (TimeInterval) async throws -> Void

    public private(set) var state: LaundryCheckout
    public private(set) var storageBlocked = false
    private var busy = false
    private let resetMarker: ResetMarker?
    private var observers: [UUID: AsyncStream<LaundryCheckout>.Continuation] = [:]

    /// Restores the persisted record (relaunch rules in `LaundryReducer.restore`).
    /// `resetMarker`: while a reset runs, no order is created (`AppReset.InProgress`).
    public init(api: LaundryOrdering, vault: LaundryVault, launcher: PaymentLauncher, hooks: LaundryHooks? = nil,
                resetMarker: ResetMarker? = nil, now: @escaping @Sendable () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { s in
                    try await Task.sleep(nanoseconds: UInt64(max(0, s) * 1_000_000_000))
                }) throws {
        self.api = api; self.vault = vault; self.launcher = launcher; self.hooks = hooks; self.now = now; self.sleep = sleep
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

    public var display: LaundryDisplay { LaundryDisplay(state) }

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
    @discardableResult
    public func confirmOrder(_ snapshot: WasherSnapshot, program: WasherProgram) async throws -> LaundryCheckout {
        try guardIdle()
        try resetMarker?.checkStart(at: now())
        guard state.canCreate else { throw LaundryEngineError.notAllowed }
        guard let draft = LaundryDraft.make(snapshot, program: program, now: now()) else { throw LaundryEngineError.washerChanged }
        return try await run(.confirm(draft, at: now()))
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
            let (next, effects) = LaundryReducer.reduce(state, event)
            try commit(next)
            for effect in effects {
                if let follow = await perform(effect) { queue.append(follow) }
            }
        }
        return state
    }

    /// Persist, then publish. A failed write blocks every later side effect.
    private func commit(_ next: LaundryCheckout) throws {
        let changed = next.persistable != state.persistable
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

        case .updateActivity(let plan):
            await hooks?.updateActivity(plan)
            return nil

        case .endActivity:
            await hooks?.endActivity()
            return nil

        case .diagnostic(let name):
            await hooks?.diagnostic(name)
            return nil
        }
    }

    static func serviceError(_ error: Error, stateChanging: Bool) -> ServiceError {
        if let e = error as? ServiceError { return stateChanging ? e.forStateChangingRequest(.ujing) : e }
        return stateChanging ? .uncertain(.ujing) : .offline
    }
}
