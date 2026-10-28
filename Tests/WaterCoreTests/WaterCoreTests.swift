import Foundation
import Testing
@testable import WaterCore

private let config = WaterConfig(secret: "test-secret", sid: "test-sid", studentID: "test-user",
    schoolID: "12345", machineID: "11223344", bleName: "test-water", typeID: 1, version: 1)
private let frame = Data([0x55,0x11,0x22,0x33,0x44] + [UInt8](repeating: 0, count: 15))
private let ack = Data([0xAA] + [UInt8](repeating: 0, count: 8))

@MainActor private final class Transport: WaterTransport {
    var replies: [Result<Data, Error>] = [.success(frame), .success(ack)]
    var writes: [Data] = []
    var expected: String?
    var preferred: String?
    var connections = 0
    var disconnections = 0
    func connect(config: WaterConfig, expectedPeripheral: String?, preferredPeripheral: String?) async throws -> String {
        connections += 1; expected = expectedPeripheral; preferred = preferredPeripheral; return "owned-device"
    }
    func exchange(_ data: Data) async throws -> Data {
        writes.append(data)
        return try replies.removeFirst().get()
    }
    func disconnect() { disconnections += 1 }
}
@MainActor private final class Provider: WaterProvider {
    var authorizations = 0
    var settlements = 0
    var authFailure: Error?
    var settleFailure: Error?
    var lastSettlement: Data?
    var pauseAuthorization = false
    var resumeAuthorization: CheckedContinuation<Void, Never>?
    var response = Authorization(machineID: "11223344", payload: Data(repeating: 0, count: 15), studentID: "001122FF")
    func authorize(config: WaterConfig, frame: Data) async throws -> Authorization {
        authorizations += 1
        if pauseAuthorization { await withCheckedContinuation { resumeAuthorization = $0 } }
        if let authFailure { throw authFailure }
        return response
    }
    var receipt = SettlementReceipt(payFen:9)
    func settle(config: WaterConfig, frame: Data) async throws -> SettlementReceipt {
        settlements += 1; lastSettlement = frame
        if let settleFailure { throw settleFailure }
        return receipt
    }
}
@MainActor private final class Store: SessionStore {
    var value: WaterSession?
    var stages: [SessionStage] = []
    var failSavingStage: SessionStage?
    var failLoading = false
    func load() throws -> WaterSession? {
        if failLoading { throw WaterError.storage }
        return value
    }
    func save(_ session: WaterSession) throws {
        if session.stage == failSavingStage { throw WaterError.storage }
        value = session; stages.append(session.stage)
    }
}

@Suite @MainActor struct ControllerTests {
    @Test func deviceBindingOnlyReadsIdentity() async throws {
        let t = Transport(), p = Provider(), s = Store()
        let c = try WaterController(transport:t,provider:p,store:s)
        let id = try await c.identify(config:config)
        #expect(id == "owned-device")
        #expect(t.writes == [Data([0xAA])] && t.disconnections == 1)
        #expect(p.authorizations == 0 && p.settlements == 0 && s.value == nil)
    }
    @Test func bindingRejectsAnotherDormWithoutAuthorization() async throws {
        let t = Transport(), p = Provider(), s = Store()
        t.replies = [.success(Data([0x55,0,0,0,0] + [UInt8](repeating:0,count:15)))]
        let c = try WaterController(transport:t,provider:p,store:s)
        await #expect(throws:WaterError.wrongDevice) { try await c.identify(config:config) }
        #expect(p.authorizations == 0 && s.value == nil && t.disconnections == 1)
    }
    @Test func bindingCannotReplaceAnActiveSession() async throws {
        let t = Transport(), p = Provider(), s = Store()
        s.value = WaterSession(stage:.active,machineID:config.machineID,peripheralID:"original")
        let c = try WaterController(transport:t,provider:p,store:s)
        await #expect(throws:WaterError.unresolved) { try await c.identify(config:config) }
        #expect(t.connections == 0 && c.session?.peripheralID == "original")
    }
    @Test func firstStartUsesVerifiedBindingButStillChecksIdentity() async throws {
        let t = Transport(), p = Provider(), s = Store()
        t.replies = [.success(Data([0x55,0,0,0,0] + [UInt8](repeating:0,count:15)))]
        let c = try WaterController(transport:t,provider:p,store:s)
        await #expect(throws:WaterError.wrongDevice) { try await c.start(config:config,preferredPeripheral:"selected-device") }
        #expect(t.preferred == "selected-device" && p.authorizations == 0 && s.value == nil)
    }
    @Test func nextStartPrefersLastPeripheralForSameWaterController() async throws {
        let t = Transport(), p = Provider(), s = Store()
        s.value = WaterSession(stage:.settled,machineID:config.machineID,peripheralID:"previous-device")
        let c = try WaterController(transport:t,provider:p,store:s)
        try await c.start(config:config)
        #expect(t.preferred == "previous-device" && t.expected == nil)
        #expect(p.authorizations == 1)
    }
    @Test func differentMachineDoesNotReuseLastPeripheralHint() async throws {
        let t = Transport(), p = Provider(), s = Store()
        s.value = WaterSession(stage:.settled,machineID:"55667788",peripheralID:"other-device")
        let c = try WaterController(transport:t,provider:p,store:s)
        try await c.start(config:config)
        #expect(t.preferred == nil)
    }
    @Test func freshAuthorization() async throws {
        let t = Transport(), p = Provider(), s = Store()
        let c = try WaterController(transport: t, provider: p, store: s)
        try await c.start(config: config)
        #expect(t.writes == [Data([0xAA]), Data(repeating: 0, count: 15)])
        #expect(p.authorizations == 1)
        #expect(s.stages == [.authorizationPending,.authorizationIssued,.authorizationWritePending,.active])
        #expect(c.session?.stage == .active)
        #expect(t.disconnections == 1)
    }
    @Test func wrongDeviceNeverRequestsAuthorization() async throws {
        let t = Transport(), p = Provider(), s = Store()
        t.replies = [.success(Data([0x55,0x55,0x66,0x77,0x88] + [UInt8](repeating: 0, count: 15)))]
        let c = try WaterController(transport: t, provider: p, store: s)
        await #expect(throws: WaterError.wrongDevice) { try await c.start(config: config) }
        #expect(p.authorizations == 0 && s.value == nil)
    }
    @Test func authorizationTimeoutBlocksRepeat() async throws {
        let t = Transport(), p = Provider(), s = Store()
        p.authFailure = WaterError.networkUncertain
        let c = try WaterController(transport: t, provider: p, store: s)
        await #expect(throws: WaterError.networkUncertain) { try await c.start(config: config) }
        await #expect(throws: WaterError.unresolved) { try await c.start(config: config) }
        #expect(s.value?.stage == .authorizationPending)
        #expect(p.authorizations == 1 && t.writes.count == 1)
    }
    @Test func notificationTimeoutRetainsCloseIdentity() async throws {
        let t = Transport(), p = Provider(), s = Store()
        t.replies = [.success(frame), .failure(WaterError.timedOut)]
        let c = try WaterController(transport: t, provider: p, store: s)
        await #expect(throws: WaterError.timedOut) { try await c.start(config: config) }
        #expect(s.value?.stage == .authorizationWritePending)
        #expect(s.value?.authorizationID == "001122FF")
        await #expect(throws: WaterError.unresolved) { try await c.start(config: config) }
        #expect(t.writes.count == 2)
    }
    @Test func ownedSessionSettlesFreshConsumption() async throws {
        let t = Transport(), p = Provider(), s = Store()
        let c = try WaterController(transport: t, provider: p, store: s)
        try await c.start(config: config)
        t.replies = [.success(Data([0xA5])), .success(frame)]
        try await c.finish(config: config)
        #expect(t.expected == "owned-device")
        #expect(t.writes.last == Data([0xAC,0x55,0x44,0x77,0xAA]))
        #expect(p.lastSettlement == frame && p.settlements == 1)
        #expect(c.session?.stage == .settled)
        #expect(c.session?.receipt?.amountYuan == Decimal(string:"0.09"))
    }
    @Test func noSessionDoesNotConnectOrWrite() async throws {
        let t = Transport(), p = Provider(), s = Store()
        let c = try WaterController(transport: t, provider: p, store: s)
        await #expect(throws: WaterError.noSession) { try await c.finish(config: config) }
        #expect(t.connections == 0 && t.writes.isEmpty && p.settlements == 0)
    }
    @Test func settlementTimeoutCannotRepeatFinancialRequest() async throws {
        let t = Transport(), p = Provider(), s = Store()
        let c = try WaterController(transport: t, provider: p, store: s)
        try await c.start(config: config)
        t.replies = [.success(Data([0xA5])), .success(frame)]
        p.settleFailure = WaterError.networkUncertain
        await #expect(throws: WaterError.networkUncertain) { try await c.finish(config: config) }
        await #expect(throws: WaterError.unresolved) { try await c.finish(config: config) }
        #expect(c.session?.stage == .settlementPending && c.session?.consumption == frame)
        #expect(p.settlements == 1)
    }
    @Test func restartRetainsUnresolvedState() async throws {
        let t = Transport(), p = Provider(), s = Store()
        s.value = WaterSession(stage: .closeWritePending, machineID: config.machineID, peripheralID: "owned-device")
        let c = try WaterController(transport: t, provider: p, store: s)
        await #expect(throws: WaterError.unresolved) { try await c.start(config: config) }
        await #expect(throws: WaterError.unresolved) { try await c.finish(config: config) }
        #expect(t.connections == 0)
    }
    @Test func persistenceFailurePreventsAuthorization() async throws {
        let t = Transport(), p = Provider(), s = Store()
        s.failSavingStage = .authorizationPending
        let c = try WaterController(transport: t, provider: p, store: s)
        await #expect(throws: WaterError.storage) { try await c.start(config: config) }
        #expect(p.authorizations == 0 && c.storageBlocked)
        await #expect(throws: WaterError.storage) { try await c.start(config: config) }
    }
    @Test func persistenceFailurePreventsCloseWrite() async throws {
        let t = Transport(), p = Provider(), s = Store()
        let c = try WaterController(transport: t, provider: p, store: s)
        try await c.start(config: config)
        s.failSavingStage = .closeWritePending
        t.replies = [.success(Data([0xA5]))]
        await #expect(throws: WaterError.storage) { try await c.finish(config: config) }
        #expect(t.writes.count == 3 && t.writes.last == Data([0xAA]))
        #expect(p.settlements == 0)
    }
    @Test func malformedProviderReplyNeverWritesAuthorization() async throws {
        let t = Transport(), p = Provider(), s = Store()
        p.response = Authorization(machineID: "11223344", payload: Data(repeating: 0, count: 15), studentID: "bad")
        let c = try WaterController(transport: t, provider: p, store: s)
        await #expect(throws: WaterError.malformedFrame) { try await c.start(config: config) }
        #expect(t.writes.count == 1 && s.value?.stage == .authorizationPending)
    }
    @Test func corruptStoreCannotBecomeEmptySession() throws {
        let s = Store(); s.failLoading = true
        #expect(throws: WaterError.storage) { try WaterController(transport: Transport(), provider: Provider(), store: s) }
    }
    @Test func concurrentShortcutAndButtonCannotAuthorizeTwice() async throws {
        let t = Transport(), p = Provider(), s = Store()
        p.pauseAuthorization = true
        let c = try WaterController(transport: t, provider: p, store: s)
        let first = Task { try await c.start(config: config) }
        while p.resumeAuthorization == nil { await Task.yield() }
        await #expect(throws: WaterError.busy) { try await c.start(config: config) }
        await #expect(throws: WaterError.busy) { try await c.finish(config: config) }
        p.resumeAuthorization?.resume()
        try await first.value
        #expect(p.authorizations == 1 && t.connections == 1)
    }
    @Test func wrongActiveStateNeverSendsCloseCommand() async throws {
        let t = Transport(), p = Provider(), s = Store()
        let c = try WaterController(transport: t, provider: p, store: s)
        try await c.start(config: config)
        t.replies = [.success(frame)]
        await #expect(throws: WaterError.notActive) { try await c.finish(config: config) }
        #expect(t.writes.count == 3 && p.settlements == 0 && s.value?.stage == .active)
    }
    @Test func invalidConsumptionNeverSettlesAnotherDevice() async throws {
        let t = Transport(), p = Provider(), s = Store()
        let c = try WaterController(transport: t, provider: p, store: s)
        try await c.start(config: config)
        t.replies = [.success(Data([0xA5])), .success(Data([0x55,0,0,0,0] + [UInt8](repeating: 0, count: 15)))]
        await #expect(throws: WaterError.wrongDevice) { try await c.finish(config: config) }
        #expect(p.settlements == 0 && s.value?.stage == .closeWritePending)
    }
    @Test func failureToPersistAuthorizationPreventsPhysicalWrite() async throws {
        let t = Transport(), p = Provider(), s = Store()
        s.failSavingStage = .authorizationWritePending
        let c = try WaterController(transport: t, provider: p, store: s)
        await #expect(throws: WaterError.storage) { try await c.start(config: config) }
        #expect(p.authorizations == 1 && t.writes.count == 1 && c.storageBlocked)
        #expect(s.value?.stage == .authorizationIssued)
    }
    @Test func missingFeeDoesNotInvalidateSuccessfulSettlement() async throws {
        let t = Transport(), p = Provider(), s = Store()
        p.receipt = SettlementReceipt(payFen:nil)
        let c = try WaterController(transport:t,provider:p,store:s)
        try await c.start(config:config)
        t.replies = [.success(Data([0xA5])),.success(frame)]
        try await c.finish(config:config)
        #expect(c.session?.stage == .settled && c.session?.receipt?.amountYuan == nil)
        #expect(p.settlements == 1)
        await #expect(throws: WaterError.noSession) { try await c.finish(config:config) }
    }
}

@Suite struct ProtocolTests {
    @Test func targetSelectionDistinguishesMissingAndAmbiguousWithoutGuessing() throws {
        #expect(throws:WaterError.targetMissing) { try WaterTargetSelection.select([],required:nil,preferred:nil) }
        #expect(throws:WaterError.targetAmbiguous) { try WaterTargetSelection.select(["a","b"],required:nil,preferred:nil) }
        #expect(try WaterTargetSelection.select(["a","b"],required:nil,preferred:"b") == "b")
        #expect(try WaterTargetSelection.select(["a"],required:nil,preferred:"old-id") == "a")
        #expect(throws:WaterError.targetAmbiguous) { try WaterTargetSelection.select(["a","b"],required:nil,preferred:"old-id") }
    }
    @Test func endingNeverFallsBackToAnotherPeripheral() throws {
        #expect(throws:WaterError.targetMissing) { try WaterTargetSelection.select(["other"],required:"owned",preferred:"other") }
        #expect(try WaterTargetSelection.select(["owned","other"],required:"owned",preferred:"other") == "owned")
    }
    @Test func splitAndCombinedFrames() throws {
        var decoder = FrameDecoder()
        #expect(try decoder.append(Data(frame.prefix(7))).isEmpty)
        #expect(try decoder.append(Data(frame.dropFirst(7)) + ack + Data([0xA5])) == [frame,ack,Data([0xA5])])
        #expect(!decoder.hasPartialFrame)
    }
    @Test func malformedFrameRejected() {
        var decoder = FrameDecoder()
        #expect(throws: WaterError.malformedFrame) { try decoder.append(Data([0x00])) }
    }
    @Test func signingEscapesMatchJavaScript() {
        #expect(WaterProtocol.encodeForm("a b+~!'()*_-.中文") == "a+b%2B%7E%21%27%28%29*_-.%E4%B8%AD%E6%96%87")
        #expect(WaterProtocol.signature(secret: "", wxcode: "") == "d41d8cd98f00b204e9800998ecf8427e")
    }
    @Test func fieldOrderAndCloseIdentity() throws {
        let value = try WaterProtocol.wxcode(config: config, frame: frame, random: "A1B2C3")
        #expect(value.hasPrefix("studentId=test-user*_schoolId=12345*_machineid=11223344*_machinedata="))
        #expect(value.hasSuffix("*_typeId=1*_alleywaytype=0*_rand=A1B2C3*_version=1"))
        #expect(try WaterProtocol.closeCommand("001122FF") == Data([0xAC,0x55,0x44,0x77,0xAA]))
    }
    @Test func strictHexDoesNotDiscardInvalidBytes() {
        #expect(Data(strictHex: "00 ZZ") == nil)
        #expect(Data(strictHex: "1") == nil)
        #expect(Data(strictHex: "aaFF") == Data([0xAA,0xFF]))
    }
    @Test func feeIsConvertedFromFenWithoutFloatingPointRounding() {
        #expect(SettlementReceipt.parse(["pay":9]).amountYuan == Decimal(string:"0.09"))
        #expect(SettlementReceipt.parse(["pay":"163"]).amountYuan == Decimal(string:"1.63"))
        #expect(SettlementReceipt.parse(["pay":0]).amountYuan == 0)
    }
    @Test func missingOrMalformedFeeNeverDisplaysZero() {
        #expect(SettlementReceipt.parse([:]).amountYuan == nil)
        for item:Any in [true, -1,"", "9abc",NSNull(),0.5] {
            #expect(SettlementReceipt.parse(["pay":item]).amountYuan == nil)
        }
    }
    @Test func preReceiptSessionRemainsReadableWithoutNewNetworkOperation() throws {
        let data = Data(#"{"stage":"settled","machineID":"11223344","peripheralID":"owned-device","startedAt":0,"endedAt":60}"#.utf8)
        let value = try JSONDecoder().decode(WaterSession.self,from:data)
        #expect(value.stage == .settled && value.receipt == nil)
        let copy = try JSONDecoder().decode(WaterSession.self,from:JSONEncoder().encode(value))
        #expect(copy == value)
    }
}
