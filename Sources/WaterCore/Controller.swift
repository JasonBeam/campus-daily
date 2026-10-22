import Foundation

@MainActor public protocol WaterTransport: AnyObject {
    func connect(config: WaterConfig, expectedPeripheral: String?) async throws -> String
    func exchange(_ data: Data) async throws -> Data
    func disconnect()
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
    public init(transport: WaterTransport, provider: WaterProvider, store: SessionStore) throws {
        self.transport = transport; self.provider = provider; self.store = store
        do { session = try store.load() } catch { throw WaterError.storage }
    }
    private func persist(_ value: WaterSession) throws {
        // Keep the more conservative in-memory state even if disk persistence fails.
        session = value
        do { try store.save(value) } catch { storageBlocked = true; throw WaterError.storage }
    }
    public func start(config: WaterConfig) async throws {
        try Task.checkCancellation()
        guard !busy else { throw WaterError.busy }
        guard !storageBlocked else { throw WaterError.storage }
        guard session == nil || session?.stage == .settled else { throw WaterError.unresolved }
        try config.validate()
        busy = true
        defer { transport.disconnect(); busy = false }
        let id = try await transport.connect(config: config, expectedPeripheral: nil)
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
        guard ack.count == 9, ack.first == 0xAA else { throw WaterError.malformedFrame }
        value.stage = .active
        try persist(value)
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
        defer { transport.disconnect(); busy = false }
        _ = try await transport.connect(config: config, expectedPeripheral: value.peripheralID)
        let first = try await transport.exchange(Data([0xAA]))
        guard first == Data([0xA5]) else { throw WaterError.notActive }
        try Task.checkCancellation()
        value.stage = .closeWritePending
        try persist(value)
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
