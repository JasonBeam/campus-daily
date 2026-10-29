import Foundation

@MainActor public protocol WaterTransport: AnyObject {
    func connect(config: WaterConfig, expectedPeripheral: String?, preferredPeripheral: String?) async throws -> String
    func exchange(_ data: Data) async throws -> Data
    func disconnect()
}

extension WaterTransport {
    public func connect(config: WaterConfig, expectedPeripheral: String?) async throws -> String {
        try await connect(config:config,expectedPeripheral:expectedPeripheral,preferredPeripheral:nil)
    }
}

public enum WaterTargetSelection {
    public static func select(_ candidates: [String], required: String?, preferred: String?) throws -> String {
        let ids = Set(candidates)
        if let required {
            guard ids.contains(required) else { throw WaterError.targetMissing }
            return required
        }
        if let preferred, ids.contains(preferred) { return preferred }
        guard !ids.isEmpty else { throw WaterError.targetMissing }
        guard ids.count == 1, let id = ids.first else { throw WaterError.targetAmbiguous }
        return id
    }
}
/// Probe with the read-only identity command before presenting same-name radios as targets.
/// RSSI orders probes only; it never establishes device ownership.
public enum WaterIdentitySelection {
    @MainActor public static func match(_ candidates: [String], machineID: String,
        probe: (String) async throws -> Data) async throws -> String {
        var seen = Set<String>()
        var sawOtherIdentity = false
        for id in candidates where seen.insert(id).inserted {
            try Task.checkCancellation()
            do {
                let frame = try await probe(id)
                let identity = try WaterProtocol.identity(frame)
                if identity == machineID.uppercased() { try Task.checkCancellation(); return id }
                sawOtherIdentity = true
            } catch is CancellationError { throw CancellationError() }
              catch WaterError.interrupted { throw WaterError.interrupted }
              catch { /* Busy, malformed and unreachable devices are not verified targets. */ }
        }
        try Task.checkCancellation()
        throw sawOtherIdentity ? WaterError.wrongDevice : WaterError.targetMissing
    }
}

@MainActor public protocol WaterProvider: AnyObject {
    func authorize(config: WaterConfig, frame: Data) async throws -> Authorization
    func settle(config: WaterConfig, frame: Data) async throws -> SettlementReceipt
}
@MainActor public protocol SessionStore: AnyObject {
    func load() throws -> WaterSession?
    func save(_ session: WaterSession) throws
}

@MainActor public final class WaterController {
    public private(set) var session: WaterSession?
    public private(set) var busy = false
    public private(set) var storageBlocked = false
    private let transport: WaterTransport
    private let provider: WaterProvider
    private let store: SessionStore
    private let diagnostics: WaterDiagnostics?
    public init(transport: WaterTransport, provider: WaterProvider, store: SessionStore, diagnostics: WaterDiagnostics? = nil) throws {
        self.transport = transport; self.provider = provider; self.store = store
        self.diagnostics = diagnostics
        do { session = try store.load() } catch { throw WaterError.storage }
    }
    private func persist(_ value: WaterSession) throws {
        // Keep the more conservative in-memory state even if disk persistence fails.
        session = value
        do { try store.save(value) } catch { storageBlocked = true; throw WaterError.storage }
        diagnostics?.record(.sessionSaved, stage: value.stage)
    }
    /// Read the hardware identity without requesting authorization or creating a session.
    public func identify(config: WaterConfig) async throws -> String {
        try Task.checkCancellation()
        guard !busy else { throw WaterError.busy }
        guard !storageBlocked else { throw WaterError.storage }
        guard session == nil || session?.stage == .settled else { throw WaterError.unresolved }
        try config.validate()
        busy = true
        defer { transport.disconnect(); busy = false }
        let id = try await transport.connect(config:config,expectedPeripheral:nil,preferredPeripheral:nil)
        let frame = try await transport.exchange(Data([0xAA]))
        guard try WaterProtocol.identity(frame) == config.machineID.uppercased() else { throw WaterError.wrongDevice }
        try Task.checkCancellation()
        return id
    }
    public func start(config: WaterConfig, preferredPeripheral: String? = nil) async throws {
        try Task.checkCancellation()
        guard !busy else { throw WaterError.busy }
        guard !storageBlocked else { throw WaterError.storage }
        guard session == nil || session?.stage == .settled else { throw WaterError.unresolved }
        try config.validate()
        busy = true
        diagnostics?.record(.startRequested, stage: session?.stage)
        var retainConnection = false
        defer { if !retainConnection { transport.disconnect() }; busy = false }
        let preferred = session?.machineID == config.machineID.uppercased() ? session?.peripheralID : nil
        let id = try await transport.connect(config: config, expectedPeripheral: nil, preferredPeripheral: preferredPeripheral ?? preferred)
        let frame = try await transport.exchange(Data([0xAA]))
        guard try WaterProtocol.identity(frame) == config.machineID.uppercased() else { throw WaterError.wrongDevice }
        try Task.checkCancellation()
        var value = WaterSession(stage: .authorizationPending, machineID: config.machineID.uppercased(), peripheralID: id)
        try persist(value)
        try Task.checkCancellation()
        let auth = try await provider.authorize(config: config, frame: frame)
        guard auth.machineID.uppercased() == value.machineID else { throw WaterError.wrongDevice }
        guard auth.payload.count == 15 else { throw WaterError.malformedFrame }
        _ = try WaterProtocol.closeCommand(auth.studentID)
        value.authorizationID = auth.studentID
        value.stage = .authorizationIssued
        try persist(value)
        try Task.checkCancellation()
        value.stage = .authorizationWritePending
        try persist(value)
        let ack = try await transport.exchange(auth.payload)
        diagnostics?.record(.authorizationReply, frame: ack)
        guard ack.count == 9, ack.first == 0xAA else { throw WaterError.malformedFrame }
        value.stage = .active
        try persist(value)
        // The official client retains BLE after authorization and clears it after close.
        // Do not impose a link-loss event on controllers which monitor the connection.
        retainConnection = true
    }
    /// Inspect the retained session without authorization, close or settlement requests.
    public func review(config: WaterConfig) async throws -> Bool {
        try Task.checkCancellation()
        guard !busy else { throw WaterError.busy }
        guard !storageBlocked else { throw WaterError.storage }
        guard var value = session, value.stage.mayClose else { throw WaterError.noSession }
        try config.validate()
        guard value.machineID == config.machineID.uppercased() else { throw WaterError.wrongDevice }
        busy = true
        diagnostics?.record(.reviewRequested, stage: value.stage)
        var retainConnection = false
        defer { if !retainConnection { transport.disconnect() }; busy = false }
        _ = try await transport.connect(config: config, expectedPeripheral: value.peripheralID)
        let reply = try await transport.exchange(Data([0xAA]))
        diagnostics?.record(.stateReply, stage: value.stage, frame: reply)
        let active = reply == Data([0xA5])
        if !active {
            guard try WaterProtocol.identity(reply) == value.machineID else { throw WaterError.wrongDevice }
        }
        value.stateReviewRequired = !active
        try persist(value)
        retainConnection = active
        return active
    }
    public func finish(config: WaterConfig) async throws {
        try Task.checkCancellation()
        guard !busy else { throw WaterError.busy }
        guard !storageBlocked else { throw WaterError.storage }
        guard var value = session, value.stage.mayClose, let authID = value.authorizationID else {
            throw session == nil || session?.stage == .settled ? WaterError.noSession : WaterError.unresolved
        }
        try config.validate()
        guard value.machineID == config.machineID.uppercased() else { throw WaterError.wrongDevice }
        let command = try WaterProtocol.closeCommand(authID)
        busy = true
        diagnostics?.record(.finishRequested, stage: value.stage)
        defer { transport.disconnect(); busy = false }
        _ = try await transport.connect(config: config, expectedPeripheral: value.peripheralID)
        let first = try await transport.exchange(Data([0xAA]))
        diagnostics?.record(.stateReply, stage: value.stage, frame: first)
        guard first == Data([0xA5]) else {
            value.stateReviewRequired = true
            try persist(value)
            diagnostics?.record(.finishBlocked, stage: value.stage, error: .notActive)
            throw WaterError.notActive
        }
        try Task.checkCancellation()
        value.stage = .closeWritePending
        value.stateReviewRequired = false
        try persist(value)
        diagnostics?.record(.closeRequested, stage: value.stage)
        let consumption = try await transport.exchange(command)
        guard try WaterProtocol.identity(consumption) == value.machineID else { throw WaterError.wrongDevice }
        value.consumption = consumption
        value.stage = .settlementPending
        try persist(value)
        try Task.checkCancellation()
        value.receipt = try await provider.settle(config: config, frame: consumption)
        value.stage = .settled
        value.endedAt = Date()
        try persist(value)
    }
}
