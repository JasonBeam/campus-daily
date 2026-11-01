import Foundation

/// The BLE link to a hot-water controller, so `ShowerEngine` runs without CoreBluetooth.
/// Implementations throw `ShowerDeviceError` (anything else is treated as `.disconnected`).
public protocol ShowerTransport: Sendable {
    /// Connects to a controller advertising `bleName` and subscribes to `FFE1`.
    /// - `required`: only this peripheral (finish/review never fall back to another one).
    /// - `preferred`: try first; else the single candidate, else identify candidates by their
    ///   `AA` identity frame against `machineID` (read-only), else `.ambiguous`/`.notFound`.
    /// Returns the peripheral identifier. Reuses a live connection to the same peripheral.
    func connect(bleName: String, machineID: String, required: String?, preferred: String?) async throws -> String
    /// Writes `command` to `FFE2` (with response) and returns the next complete notification frame.
    func exchange(_ command: Data) async throws -> Data
    func disconnect() async
}

/// Peripheral choice without guessing (ported from the existing app).
public enum ShowerTargetSelection {
    public static func select(_ candidates: [String], required: String?, preferred: String?) throws -> String {
        let ids = Set(candidates)
        if let required {
            guard ids.contains(required) else { throw ShowerDeviceError.notFound }
            return required
        }
        if let preferred, ids.contains(preferred) { return preferred }
        guard !ids.isEmpty else { throw ShowerDeviceError.notFound }
        guard ids.count == 1, let id = ids.first else { throw ShowerDeviceError.ambiguous }
        return id
    }

    /// Probes same-name candidates with the read-only `AA` command and returns the one whose
    /// identity is `machineID`. RSSI only orders probes; it never establishes ownership.
    /// Runs on the caller's actor, so a probe that touches actor state (the Bluetooth transport
    /// on the main actor) is never sent elsewhere.
    public static func identify(_ candidates: [String], machineID: String,
                                isolation: isolated (any Actor)? = #isolation,
                                probe: (String) async throws -> Data) async throws -> String {
        var seen = Set<String>()
        var sawOther = false
        for id in candidates where seen.insert(id).inserted {
            try Task.checkCancellation()
            do {
                let frame = try await probe(id)
                if ShowerFrames.identity(frame) == machineID.uppercased() { return id }
                if ShowerFrames.identity(frame) != nil { sawOther = true }
            } catch is CancellationError {
                throw ShowerDeviceError.interrupted
            } catch ShowerDeviceError.interrupted {
                throw ShowerDeviceError.interrupted
            } catch {
                // Busy, malformed and unreachable devices are not verified targets.
            }
        }
        try Task.checkCancellation()
        throw sawOther ? ShowerDeviceError.ambiguous : ShowerDeviceError.notFound
    }
}

/// Reminder / diagnostics hooks (App: UNUserNotificationCenter, diagnostic log). Optional.
public protocol ShowerHooks: Sendable {
    /// "还没结束洗澡？" after the configured minutes in writePending/running; asked for when the
    /// water starts (the same moment as `ShowerState.startedAt`).
    func scheduleUnsettledReminder(after seconds: TimeInterval) async
    func cancelUnsettledReminder() async
    /// Event names only (no ids, frames or tokens).
    func diagnostic(_ event: String) async
}

public enum ShowerEngineError: Error, Equatable, Sendable {
    /// Another operation is running.
    case busy
    /// The current record must be finished/settled/reviewed first.
    case blocked
    /// Not allowed in the current state.
    case notAllowed
    /// The binding is for another controller than the session.
    case wrongBinding
    /// A session write failed: nothing more is sent until relaunch (fail closed).
    case storage
}

/// Drives `ShowerReducer`: persists every state before running its effects, talks to the
/// controller through `ShowerTransport` and to the platform through `ShowerGateway`.
/// Settle is never retried automatically.
public actor ShowerEngine {
    public struct Configuration: Sendable {
        public var bleName: String
        public var reminderMinutes: Int
        public init(bleName: String, reminderMinutes: Int = 30) { self.bleName = bleName; self.reminderMinutes = reminderMinutes }
    }

    let transport: ShowerTransport
    let gateway: ShowerGateway
    let vault: ShowerVault
    let hooks: ShowerHooks?
    let configuration: Configuration
    let now: @Sendable () -> Date

    public private(set) var state: ShowerState
    public private(set) var storageBlocked = false
    private var busy = false
    private var binding: ShowerBinding?
    private let resetMarker: ResetMarker?
    private var observers: [UUID: AsyncStream<ShowerState>.Continuation] = [:]
    /// 取消 was accepted for the running start: its authorize request never leaves.
    private var startCancelled = false
    /// The running start's authorize request has left: from here a cancel could leave an
    /// authorization nobody knows about, so none is accepted.
    private var authorizeLeft = false

    /// Restores the persisted session (relaunch rules in `ShowerReducer.restore`).
    /// `resetMarker`: while a reset runs, `start` is refused (`AppReset.InProgress`).
    public init(transport: ShowerTransport, gateway: ShowerGateway, vault: ShowerVault, configuration: Configuration,
                hooks: ShowerHooks? = nil, resetMarker: ResetMarker? = nil, now: @escaping @Sendable () -> Date = Date.init) throws {
        self.transport = transport; self.gateway = gateway; self.vault = vault; self.hooks = hooks
        self.configuration = configuration; self.now = now; self.resetMarker = resetMarker
        let persisted: ShowerState?
        do { persisted = try vault.showerState() } catch { throw ShowerEngineError.storage }
        let restored = ShowerReducer.restore(persisted)
        var blocked = false
        if let persisted, restored.persistable != persisted {
            do { try vault.saveShowerState(restored.persistable) } catch { blocked = true }
        }
        self.storageBlocked = blocked
        self.state = restored
    }

    public var display: ShowerDisplay { ShowerDisplay(state) }

    /// Current state first, then every change.
    public func updates() -> AsyncStream<ShowerState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ShowerState>.makeStream(bufferingPolicy: .bufferingNewest(16))
        continuation.yield(state)
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    // MARK: User actions

    /// 开水: connect + identity probe, authorize, write the authorization.
    @discardableResult
    public func start(_ b: ShowerBinding) async throws -> ShowerState {
        try guardIdle()
        try resetMarker?.checkStart(at: now())
        guard state.canStart else { throw ShowerEngineError.blocked }
        let preferred = b.peripheralID ?? (state.machineID == b.machineId.uppercased() ? state.peripheralID : nil)
        startCancelled = false; authorizeLeft = false
        return try await run(b, .start(machineID: b.machineId, preferredPeripheral: preferred))
    }

    /// 取消 while connecting. True: the start stops before its authorize request leaves (nothing
    /// issued) and ends as a connect failure that leaves no record; the caller may then cancel
    /// its task to cut the Bluetooth connect short. False once the request has left (or there
    /// is no start running): the start goes on and ends as it would have.
    public func cancelStart() -> Bool {
        guard busy, state.phase == .authorizing, !authorizeLeft else { return false }
        startCancelled = true
        return true
    }

    /// 结束: probe (`A5` required), close, settle once.
    @discardableResult
    public func finish(_ b: ShowerBinding) async throws -> ShowerState {
        try guardIdle()
        guard state.canFinish else { throw ShowerEngineError.notAllowed }
        guard state.machineID == b.machineId.uppercased() else { throw ShowerEngineError.wrongBinding }
        return try await run(b, .finish)
    }

    /// Read-only state probe of the session's controller.
    @discardableResult
    public func review(_ b: ShowerBinding) async throws -> ShowerState {
        try guardIdle()
        guard state.canFinish else { throw ShowerEngineError.notAllowed }
        guard state.machineID == b.machineId.uppercased() else { throw ShowerEngineError.wrongBinding }
        return try await run(b, .review)
    }

    /// First tap of a manual settle retry (UI then asks again).
    @discardableResult
    public func requestSettleRetry() async throws -> ShowerState {
        try guardIdle()
        guard state.canRetrySettle else { throw ShowerEngineError.notAllowed }
        return try await run(nil, .requestSettleRetry)
    }

    /// Second confirmation: sends settle once more (idempotency unknown; recorded).
    @discardableResult
    public func confirmSettleRetry(_ b: ShowerBinding) async throws -> ShowerState {
        try guardIdle()
        guard state.canRetrySettle, state.settleRetryArmed else { throw ShowerEngineError.notAllowed }
        guard state.machineID == b.machineId.uppercased() else { throw ShowerEngineError.wrongBinding }
        return try await run(b, .confirmSettleRetry)
    }

    /// After the user checked the official hot-water record.
    @discardableResult
    public func resolveManually() async throws -> ShowerState {
        try guardIdle()
        guard state.canResolveManually else { throw ShowerEngineError.notAllowed }
        return try await run(nil, .resolveManually)
    }

    /// Clears a finished or harmless record. `only`: the record the caller saw; when the record
    /// is no longer that one (a new start has run since), nothing is cleared.
    @discardableResult
    public func dismiss(only expected: ShowerState? = nil) async throws -> ShowerState {
        try guardIdle()
        if let expected, expected != state { return state }
        return try await run(nil, .dismiss)
    }

    // MARK: Loop

    private func guardIdle() throws {
        guard !busy else { throw ShowerEngineError.busy }
        guard !storageBlocked else { throw ShowerEngineError.storage }
    }

    private func run(_ b: ShowerBinding?, _ first: ShowerEvent) async throws -> ShowerState {
        busy = true
        binding = b
        defer { busy = false; binding = nil }
        var queue = [first]
        while !queue.isEmpty {
            let event = queue.removeFirst()
            let (next, effects) = ShowerReducer.reduce(state, event)
            try await commit(next)
            for effect in effects {
                if let follow = await perform(effect) { queue.append(follow) }
            }
        }
        // The controller answered with this machine's identity before authorize: remember it,
        // also when the authorization write was not acknowledged.
        if state.phase == .running || state.phase == .writePending { rememberPeripheral() }
        return state
    }

    /// Persist, then publish. A failed write blocks every later side effect.
    private func commit(_ next: ShowerState) async throws {
        let changed = next.persistable != state.persistable
        state = next
        if changed {
            do { try vault.saveShowerState(next.persistable) }
            catch {
                storageBlocked = true
                publish()
                await transport.disconnect()
                throw ShowerEngineError.storage
            }
        }
        publish()
    }

    private func publish() {
        for c in observers.values { c.yield(state) }
    }

    private func rememberPeripheral() {
        guard let id = state.peripheralID, var b = try? vault.binding(), b.machineId.uppercased() == state.machineID,
              b.peripheralID != id else { return }
        b.peripheralID = id
        try? vault.saveBinding(b)
    }

    private func perform(_ effect: ShowerEffect) async -> ShowerEvent? {
        switch effect {
        case .connectAndProbe(let machine, let preferred):
            do {
                let id = try await transport.connect(bleName: configuration.bleName, machineID: machine, required: nil, preferred: preferred)
                let frame = try await transport.exchange(ShowerFrames.probeCommand)
                return .connected(peripheralID: id, probe: frame)
            } catch {
                return .connectFailed(Self.deviceError(error))
            }

        case .authorize(let frame):
            guard let b = binding, !Task.isCancelled, !startCancelled else { return .cancelledBeforeSend }
            authorizeLeft = true
            do {
                let auth = try await gateway.authorize(b, frame: frame)
                return .authorized(auth, at: now())
            }
            catch let e as ServiceError { return .authorizeFailed(e) }
            catch { return .authorizeFailed(.uncertain(.lxt6)) }

        case .writeAuthorization(let payload):
            do { return .writeReplied(try await transport.exchange(payload)) }
            catch { return .writeFailed(Self.deviceError(error)) }

        case .probe(let peripheral):
            do {
                _ = try await transport.connect(bleName: configuration.bleName, machineID: state.machineID ?? "",
                                                required: peripheral, preferred: nil)
                return .probeReplied(try await transport.exchange(ShowerFrames.probeCommand))
            } catch {
                return .probeFailed(Self.deviceError(error))
            }

        case .sendClose(let command):
            guard !Task.isCancelled else { return .cancelledBeforeSend }
            do { return .closeReplied(try await transport.exchange(command)) }
            catch { return .closeFailed(Self.deviceError(error)) }

        case .settle(let frame):
            guard let b = binding, !Task.isCancelled else { return .cancelledBeforeSend }
            do { return .settled(try await gateway.settle(b, frame: frame), at: now()) }
            catch let e as ServiceError { return .settleFailed(e) }
            catch { return .settleFailed(.uncertain(.lxt6)) }

        case .releaseDevice:
            await transport.disconnect()
            return nil

        case .forgetPeripheral(let id):
            if var b = try? vault.binding(), b.machineId.uppercased() == state.machineID, b.peripheralID == id {
                b.peripheralID = nil
                try? vault.saveBinding(b)
            }
            return nil

        case .scheduleReminder:
            await hooks?.scheduleUnsettledReminder(after: TimeInterval(configuration.reminderMinutes * 60))
            return nil

        case .cancelReminder:
            await hooks?.cancelUnsettledReminder()
            return nil

        case .diagnostic(let name):
            await hooks?.diagnostic(name)
            return nil
        }
    }

    static func deviceError(_ error: Error) -> ShowerDeviceError {
        if let e = error as? ShowerDeviceError { return e }
        if error is CancellationError { return .interrupted }
        return .disconnected
    }
}
