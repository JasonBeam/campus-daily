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

/// Thrown by `ShowerTransport.exchange` when the command never reached the controller: the
/// task was cancelled or the link was unusable before the write, or the controller refused the
/// write itself with an ATT error response (`ShowerWriteDelivery`). `cause` is what the user is told.
public struct ShowerCommandNotSent: Error, Sendable, Equatable {
    public var cause: ShowerDeviceError
    public init(_ cause: ShowerDeviceError) { self.cause = cause }
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
            } catch let e as ShowerCommandNotSent where e.cause == .interrupted {
                throw ShowerDeviceError.interrupted
            } catch {
                // Busy, malformed and unreachable devices are not verified targets.
            }
        }
        try Task.checkCancellation()
        throw sawOther ? ShowerDeviceError.ambiguous : ShowerDeviceError.notFound
    }
}

/// Diagnostics hook. Optional. (Reminders follow the published state in the app.)
public protocol ShowerHooks: Sendable {
    /// The engine's notes (no ids, frames or tokens); tests observe them.
    func diagnostic(_ event: ShowerDiagnostic) async
    /// Every step of the record for the TestFlight debug log (`DebugLogShowerHooks`). Must not
    /// block: it runs inside the engine's steps.
    func record(_ event: DebugEvent)
}

public extension ShowerHooks {
    func diagnostic(_ event: ShowerDiagnostic) async {}
    func record(_ event: DebugEvent) {}
}

/// The app's hooks: every event and note goes to the debug log (kept on TestFlight only).
public struct DebugLogShowerHooks: ShowerHooks {
    let log: any DebugLogSink
    public init(_ log: any DebugLogSink) { self.log = log }
    public func diagnostic(_ event: ShowerDiagnostic) async { log.record(.showerNote(event)) }
    public func record(_ event: DebugEvent) { log.record(event) }
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
    /// The saved session record is there but can't be decoded: nothing is sent, and a relaunch
    /// doesn't help.
    case unreadableRecord
    /// No hot-water platform profile: the settlement couldn't be sent, so 结束 (close, then
    /// settle) and a settle retry are refused before anything goes out.
    case platformMissing
}

/// Drives `ShowerReducer`: persists every state before running its effects, talks to the
/// controller through `ShowerTransport` and to the platform through `ShowerGateway`.
/// Settle is never retried automatically.
public actor ShowerEngine {
    public struct Configuration: Sendable {
        public var bleName: String
        public init(bleName: String) { self.bleName = bleName }
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
        do { persisted = try vault.showerState() }
        catch ShowerEngineError.unreadableRecord {
            hooks?.record(.showerRestore(saved: nil, restored: .idle, unreadable: true))
            throw ShowerEngineError.unreadableRecord
        }
        catch {
            hooks?.record(.showerRestore(saved: nil, restored: .idle, unreadable: true))
            throw ShowerEngineError.storage
        }
        let restored = ShowerReducer.restore(persisted)
        hooks?.record(.showerRestore(saved: persisted?.phase, restored: restored.phase, unreadable: false))
        var blocked = false
        if let persisted, restored.persistable != persisted {
            do { try vault.saveShowerState(restored.persistable) } catch { blocked = true }
        }
        self.storageBlocked = blocked
        self.state = restored
    }

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

    /// 开始洗澡 from Siri or Shortcuts. Over a shower that is over (`ShowerState.showerOver`) it is
    /// the page's 开始下一次洗澡 (`startNext`): a read-only probe, nothing sent while the
    /// controller is in use, else the old record kept and read back before one new
    /// authorization; it is never closed or settled. Otherwise the usual start.
    @discardableResult
    public func startOrNext(_ b: ShowerBinding) async throws -> ShowerState {
        let next = state.showerOver && state.canStartNext
        hooks?.record(.showerAction(.shortcutStart(next: next)))
        if next { return try await startNext(b) }
        return try await start(b)
    }

    /// 开水: connect + identity probe, authorize, write the authorization.
    @discardableResult
    public func start(_ b: ShowerBinding) async throws -> ShowerState {
        try guardIdle()
        try resetMarker?.checkStart(at: now())
        guard state.canStart else { throw ShowerEngineError.blocked }
        hooks?.record(.showerAction(.start(machine: .machine(b.machineId))))
        let preferred = b.peripheralID ?? (state.machineID == b.machineId.uppercased() ? state.peripheralID : nil)
        startCancelled = false; authorizeLeft = false
        return try await run(b, .start(machineID: b.machineId, preferredPeripheral: preferred))
    }

    /// 取消 while connecting. True: the start stops before its authorize request leaves (nothing
    /// issued) and ends as a connect failure that leaves no record; the caller may then cancel
    /// its task to cut the Bluetooth connect short. False once the request has left (or there
    /// is no start running): the start goes on and ends as it would have.
    public func cancelStart() -> Bool {
        guard busy, state.phase == .authorizing, !authorizeLeft else {
            hooks?.record(.showerAction(.cancelStart(accepted: false)))
            return false
        }
        startCancelled = true
        hooks?.record(.showerAction(.cancelStart(accepted: true)))
        return true
    }

    /// The next use over a record that waits for the user's check (`ShowerState.canStartNext`),
    /// such as a shower stopped with the controller's own button. The controller is probed
    /// first: still in use (`A5`), the link is let go and the record is marked
    /// `waitingForRelease`; another or no controller changes nothing. Idle with this machine's
    /// identity, the record is kept as it is (`ShowerVault.retainShower`, never settled), and
    /// only then a new record asks for a new authorization with that fresh identity frame.
    @discardableResult
    public func startNext(_ b: ShowerBinding) async throws -> ShowerState {
        try guardIdle()
        try resetMarker?.checkStart(at: now())
        guard state.canStartNext else { throw ShowerEngineError.notAllowed }
        let machine = b.machineId.uppercased()
        guard state.machineID == machine else { throw ShowerEngineError.wrongBinding }
        hooks?.record(.showerAction(.startNext(machine: .machine(machine))))
        busy = true
        defer { busy = false; binding = nil }
        let previous = state
        let peripheral: String
        let probe: Data
        let preferred = b.peripheralID ?? previous.peripheralID
        do {
            peripheral = try await connect(machineID: machine, required: nil, preferred: preferred)
            probe = try await transport.exchange(ShowerFrames.probeCommand)
            logProbe(probe, machine: machine)
        } catch {
            await transport.disconnect()
            return noticed(.device(Self.deviceError(error)))
        }
        // Cancelled while it connected or probed: whatever the controller answered, nothing
        // changes (no mark, no record kept, no authorization).
        guard !Task.isCancelled else {
            await transport.disconnect()
            await hooks?.diagnostic(.nextUseCancelled)
            return noticed(.device(.interrupted))
        }
        switch ShowerFrames.classify(probe) {
        case .active:
            var waiting = previous
            waiting.waitingForRelease = true
            waiting.notice = .device(.busy)
            try await commit(waiting)
            await transport.disconnect()
            await hooks?.diagnostic(.nextUseDeviceBusy)
            return state
        case .idle(let id) where id == machine:
            break
        case .idle:
            await transport.disconnect()
            await hooks?.diagnostic(.nextUseWrongDevice)
            return noticed(.wrongDevice)
        case .unreadable:
            await transport.disconnect()
            await hooks?.diagnostic(.nextUseUnreadable)
            return noticed(.device(.malformedFrame))
        }
        do { try vault.retainShower(previous.persistable) }
        catch {
            await hooks?.diagnostic(.nextUseKeepFailed)
            storageBlocked = true
            publish()
            await transport.disconnect()
            throw ShowerEngineError.storage
        }
        await hooks?.diagnostic(.nextUseRecordKept)
        startCancelled = false; authorizeLeft = false
        binding = b
        do {
            try await commit(ShowerState(phase: .authorizing, machineID: machine, peripheralID: previous.peripheralID,
                                         lastReceipt: previous.lastReceipt))
        } catch {
            // The new record could not be saved: nothing went out, and the one in place (the
            // stopped shower, still on disk) is what the page shows again.
            binding = nil
            state = previous
            publish()
            await hooks?.diagnostic(.nextUseNotSaved)
            throw error
        }
        return try await loop(.connected(peripheralID: peripheral, probe: probe))
    }

    /// A line for the user over an unchanged record (not saved: `persistable` drops it).
    private func noticed(_ notice: ShowerNotice) -> ShowerState {
        state.notice = notice
        publish()
        return state
    }

    /// 结束: probe (`A5` required), close, settle once.
    @discardableResult
    public func finish(_ b: ShowerBinding) async throws -> ShowerState {
        try guardIdle()
        guard state.canFinish else { throw ShowerEngineError.notAllowed }
        guard state.machineID == b.machineId.uppercased() else { throw ShowerEngineError.wrongBinding }
        // Closing the water without a way to settle would leave a charge nobody can send.
        guard gateway.isAvailable else { throw ShowerEngineError.platformMissing }
        hooks?.record(.showerAction(.finish))
        return try await run(b, .finish)
    }

    /// Read-only state probe of the session's controller (also from an unconfirmed close).
    @discardableResult
    public func review(_ b: ShowerBinding) async throws -> ShowerState {
        try guardIdle()
        guard state.canReview else { throw ShowerEngineError.notAllowed }
        guard state.machineID == b.machineId.uppercased() else { throw ShowerEngineError.wrongBinding }
        hooks?.record(.showerAction(.review))
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
        guard gateway.isAvailable else { throw ShowerEngineError.platformMissing }
        return try await run(b, .confirmSettleRetry)
    }

    /// The page was left with the retry armed: its first tap no longer counts.
    @discardableResult
    public func disarmSettleRetry() async throws -> ShowerState {
        try guardIdle()
        guard state.settleRetryArmed else { return state }
        return try await run(nil, .disarmSettleRetry)
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
        hooks?.record(.showerAction(.dismiss))
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
        return try await loop(first)
    }

    private func loop(_ first: ShowerEvent) async throws -> ShowerState {
        var queue = [first]
        while !queue.isEmpty {
            let event = queue.removeFirst()
            var (next, effects) = ShowerReducer.reduce(state, event)
            // Back on the timer from the unsure face: the reminder counts from now (saved, so a
            // relaunch counts from the same moment).
            if state.phase == .failed, next.mayBeFlowing { next.timerResumedAt = now() }
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
        if let hooks {
            let before = DebugShowerState(state), after = DebugShowerState(next)
            if before != after { hooks.record(.showerPhase(from: state.phase, to: after)) }
        }
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
                let id = try await connect(machineID: machine, required: nil, preferred: preferred)
                let frame = try await transport.exchange(ShowerFrames.probeCommand)
                logProbe(frame, machine: machine)
                return .connected(peripheralID: id, probe: frame)
            } catch {
                return .connectFailed(Self.deviceError(error))
            }

        case .authorize(let frame):
            guard let b = binding, !Task.isCancelled, !startCancelled else { return .cancelledBeforeSend }
            authorizeLeft = true
            hooks?.record(.lxtAuthorize(.sent))
            do {
                let auth = try await gateway.authorize(b, frame: frame)
                hooks?.record(.lxtAuthorize(.ok(dataLength: auth.payload.count,
                                                idIsHex8: ShowerFrames.closeCommand(authorizationID: auth.authorizationID) != nil)))
                return .authorized(auth, at: now())
            }
            catch let e as ServiceError { hooks?.record(.lxtAuthorize(.failed(DebugError(e)))); return .authorizeFailed(e) }
            catch { hooks?.record(.lxtAuthorize(.failed(DebugError(error)))); return .authorizeFailed(.uncertain(.lxt6)) }

        case .writeAuthorization(let payload):
            guard !Task.isCancelled else { hooks?.record(.bleAuthWrite(.notSent)); return .cancelledBeforeSend }
            do {
                let reply = try await transport.exchange(payload)
                hooks?.record(.bleAuthWrite(.replied(DebugFrame(reply), matches: ShowerFrames.isAck(reply))))
                return .writeReplied(reply)
            }
            catch is ShowerCommandNotSent { hooks?.record(.bleAuthWrite(.notSent)); return .cancelledBeforeSend }
            catch { hooks?.record(.bleAuthWrite(.failed(Self.deviceError(error)))); return .writeFailed(Self.deviceError(error)) }

        case .probe(let peripheral):
            do {
                _ = try await connect(machineID: state.machineID ?? "", required: peripheral, preferred: nil)
                let frame = try await transport.exchange(ShowerFrames.probeCommand)
                logProbe(frame, machine: state.machineID)
                return .probeReplied(frame)
            } catch {
                return .probeFailed(Self.deviceError(error))
            }

        case .sendClose(let command):
            guard !Task.isCancelled else { hooks?.record(.bleClose(.notSent)); return .cancelledBeforeSend }
            do {
                let reply = try await transport.exchange(command)
                let consumption = ShowerFrames.identity(reply).map { $0 == state.machineID } ?? false
                hooks?.record(.bleClose(.replied(DebugFrame(reply), matches: consumption)))
                return .closeReplied(reply)
            }
            catch is ShowerCommandNotSent { hooks?.record(.bleClose(.notSent)); return .cancelledBeforeSend }
            catch { hooks?.record(.bleClose(.failed(Self.deviceError(error)))); return .closeFailed(Self.deviceError(error)) }

        case .settle(let frame):
            guard let b = binding, !Task.isCancelled else { hooks?.record(.lxtSettle(.notSent)); return .cancelledBeforeSend }
            hooks?.record(.lxtSettle(.sent))
            do {
                let receipt = try await gateway.settle(b, frame: frame)
                hooks?.record(.lxtSettle(.ok(fen: receipt.amount?.fen)))
                return .settled(receipt, at: now())
            }
            catch let e as ServiceError { hooks?.record(.lxtSettle(.failed(DebugError(e)))); return .settleFailed(e) }
            catch { hooks?.record(.lxtSettle(.failed(DebugError(error)))); return .settleFailed(.uncertain(.lxt6)) }

        case .releaseDevice:
            await transport.disconnect()
            return nil

        case .forgetPeripheral(let id):
            if var b = try? vault.binding(), b.machineId.uppercased() == state.machineID, b.peripheralID == id {
                b.peripheralID = nil
                try? vault.saveBinding(b)
            }
            return nil

        case .diagnostic(let name):
            await hooks?.diagnostic(name)
            return nil
        }
    }

    /// Connects and logs how (`ble.connect`): never which peripheral, only whether it is the one
    /// the record already had.
    private func connect(machineID: String, required: String?, preferred: String?) async throws -> String {
        let target: DebugConnect.Target = required != nil ? .required : (preferred != nil ? .preferred : .scanned)
        let known = required ?? preferred
        do {
            let id = try await transport.connect(bleName: configuration.bleName, machineID: machineID, required: required, preferred: preferred)
            hooks?.record(.bleConnect(DebugConnect(error: nil, target: target, samePeripheral: known.map { $0 == id })))
            return id
        } catch {
            hooks?.record(.bleConnect(DebugConnect(error: Self.deviceError(error), target: target, samePeripheral: nil)))
            throw error
        }
    }

    private func logProbe(_ frame: Data, machine: String?) {
        hooks?.record(.bleProbe(DebugFrame(frame), DebugProbeVerdict(frame, machineID: machine)))
    }

    public static func deviceError(_ error: Error) -> ShowerDeviceError {
        if let e = error as? ShowerDeviceError { return e }
        if let e = error as? ShowerCommandNotSent { return e.cause }
        if error is CancellationError { return .interrupted }
        return .disconnected
    }
}
