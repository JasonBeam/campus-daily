import Foundation
import Testing
@testable import WaterCore

@Suite @MainActor struct WaterNextUseTests {
    private let config = WaterConfig(secret:"fixture",sid:"fixture",studentID:"student",schoolID:"school",machineID:"11223344",bleName:"fixture",typeID:1,version:1)
    private var idle: Data { Data([0x55,0x11,0x22,0x33,0x44] + [UInt8](repeating:0,count:15)) }
    private var ack: Data { Data([0xAA] + [UInt8](repeating:0,count:8)) }
    @MainActor private final class Radio: WaterTransport {
        var replies: [Data] = []; var writes: [Data] = []; var disconnects = 0
        func connect(config:WaterConfig,expectedPeripheral:String?,preferredPeripheral:String?) async throws -> String { "radio" }
        func exchange(_ data:Data) async throws -> Data { writes.append(data); return replies.removeFirst() }
        func disconnect() { disconnects += 1 }
    }
    @MainActor private final class Store: SessionStore {
        var current:WaterSession?; var history:[WaterSession] = []
        var failArchive = false; var failSave = false
        func load() throws -> WaterSession? { current }
        func save(_ value:WaterSession) throws { if failSave { throw WaterError.storage }; current = value }
        func archive(_ value:WaterSession) throws {
            if failArchive { throw WaterError.storage }
            if !history.contains(value) { history.append(value) }
        }
        func loadArchive() throws -> [WaterSession] { history }
    }
    @MainActor private final class Service: WaterProvider {
        let store:Store; var calls = 0; var settlements = 0; var failure:WaterError?
        init(_ store:Store) { self.store = store }
        func authorize(config:WaterConfig,frame:Data) async throws -> Authorization {
            calls += 1
            #expect(!store.history.isEmpty && store.current?.stage == .authorizationPending)
            if let failure { throw failure }
            return Authorization(machineID:config.machineID,payload:Data(repeating:0,count:15),studentID:"00112233")
        }
        func settle(config:WaterConfig,frame:Data) async throws -> SettlementReceipt {
            settlements += 1; return SettlementReceipt(payFen:1)
        }
    }
    @Test(arguments:[SessionStage.active,.authorizationPending,.authorizationIssued,.authorizationWritePending,.closeWritePending,.settlementPending])
    func freshNextUsePreservesEveryUnresolvedStageWithoutSettlingIt(stage:SessionStage) async throws {
        let s=Store(),r=Radio(),p=Service(s)
        var old=WaterSession(stage:stage,machineID:config.machineID,peripheralID:"radio")
        old.authorizationID="AABBCCDD"; old.stateReviewRequired=true
        if stage == .settlementPending { old.consumption=idle }
        s.current=old; r.replies=[idle,ack]
        let c=try WaterController(transport:r,provider:p,store:s)
        try await c.startNext(config:config)
        #expect(s.history == [old] && s.history[0].receipt == nil)
        #expect(c.session?.stage == .active && c.session?.authorizationID == "00112233")
        #expect(p.calls == 1 && p.settlements == 0)
        #expect(r.writes == [Data([0xAA]),Data(repeating:0,count:15)])
        let restarted=try WaterController(transport:r,provider:p,store:s)
        #expect(restarted.archivedSessions == [old] && restarted.session?.stage == .active)
    }
    @Test func occupiedDeviceNeverArchivesOrRequestsAuthorization() async throws {
        let s=Store(),r=Radio(),p=Service(s)
        let old=WaterSession(stage:.closeWritePending,machineID:config.machineID,peripheralID:"radio")
        s.current=old;r.replies=[Data([0xA5])]
        let c=try WaterController(transport:r,provider:p,store:s)
        await #expect(throws:WaterError.controllerInUse) { try await c.startNext(config:config) }
        #expect(s.current?.startedAt == old.startedAt && s.current?.isWaitingForRelease == true)
        #expect(s.history.isEmpty && p.calls == 0 && p.settlements == 0)
        #expect(r.writes == [Data([0xAA])] && r.disconnects == 1)
    }
    @Test func busyNextUseKeepsLinkReleasedAcrossRelaunchUntilExplicitRetry() async throws {
        let s=Store(),r=Radio(),p=Service(s)
        let old=WaterSession(stage:.active,machineID:config.machineID,peripheralID:"radio")
        s.current=old;r.replies=[Data([0xA5])]
        let c=try WaterController(transport:r,provider:p,store:s)
        await #expect(throws:WaterError.controllerInUse) { try await c.startNext(config:config) }
        let reopened=try WaterController(transport:r,provider:p,store:s)
        #expect(reopened.session?.isWaitingForRelease == true && !reopened.mayReviewAutomatically)
        await #expect(throws:WaterError.unresolved) { try await reopened.finish(config:config) }
        #expect(p.calls == 0 && p.settlements == 0 && r.disconnects == 1)
        // A manual check returning A5 also releases the connection, rather than holding it open.
        r.replies=[Data([0xA5])]
        #expect(try await reopened.review(config:config))
        #expect(r.disconnects == 2 && !reopened.mayReviewAutomatically)
        let retained=reopened.session!
        r.replies=[idle,ack]
        try await reopened.startNext(config:config)
        #expect(s.history == [retained] && reopened.session?.stage == .active)
        #expect(reopened.mayReviewAutomatically && p.calls == 1 && p.settlements == 0)
    }
    @Test func wrongControllerNeverArchivesOrAuthorizes() async throws {
        let s=Store(),r=Radio(),p=Service(s)
        let old=WaterSession(stage:.active,machineID:config.machineID,peripheralID:"radio")
        s.current=old;r.replies=[Data([0x55] + [UInt8](repeating:0,count:19))]
        let c=try WaterController(transport:r,provider:p,store:s)
        await #expect(throws:WaterError.wrongDevice) { try await c.startNext(config:config) }
        #expect(s.current == old && s.history.isEmpty && p.calls == 0)
    }
    @Test func cannotLosePreviousRecordOnArchiveOrCurrentSaveFailure() async throws {
        for archiveFailure in [true,false] {
            let s=Store(),r=Radio(),p=Service(s)
            let old=WaterSession(stage:.settlementPending,machineID:config.machineID,peripheralID:"radio")
            s.current=old;s.failArchive=archiveFailure;s.failSave = !archiveFailure;r.replies=[idle]
            let c=try WaterController(transport:r,provider:p,store:s)
            await #expect(throws:WaterError.storage) { try await c.startNext(config:config) }
            #expect(p.calls == 0 && p.settlements == 0 && c.storageBlocked)
            #expect(s.current == old)
            #expect(archiveFailure ? s.history.isEmpty : s.history == [old])
        }
    }
    @Test(arguments:[WaterError.officialUnfinishedOrder,.networkUncertain])
    func rejectedOrUncertainAuthorizationIsNotReplayed(failure:WaterError) async throws {
        let s=Store(),r=Radio(),p=Service(s)
        let old=WaterSession(stage:.closeWritePending,machineID:config.machineID,peripheralID:"radio")
        s.current=old;r.replies=[idle];p.failure=failure
        let c=try WaterController(transport:r,provider:p,store:s)
        await #expect(throws:failure) { try await c.startNext(config:config) }
        #expect(s.history == [old] && s.current?.stage == .authorizationPending)
        #expect(p.calls == 1 && p.settlements == 0 && r.writes == [Data([0xAA])])
    }
    @Test func official4060IsDistinctFromSuccessfulAuthorization() throws {
        #expect(throws:WaterError.officialUnfinishedOrder) {
            try HTTPSWaterProvider.decodeResponse(Data(#"{"code":4060,"data":{}}"#.utf8))
        }
        #expect(throws:WaterError.provider) {
            try HTTPSWaterProvider.decodeResponse(Data(#"{"code":true,"data":{}}"#.utf8))
        }
        #expect(try HTTPSWaterProvider.decodeResponse(Data(#"{"code":0,"data":{"fixture":1}}"#.utf8))["fixture"] as? Int == 1)
    }
    @Test(arguments:[1,7], [SessionStage.active,.closeWritePending,.settlementPending])
    func coldLaunchWithPreviousDayLegacyRecordCanStartNext(days:Int,stage:SessionStage) async throws {
        let s=Store(),r=Radio(),p=Service(s)
        var retained=WaterSession(stage:stage,machineID:config.machineID,peripheralID:"radio")
        retained.authorizationID="AABBCCDD"
        if stage == .settlementPending { retained.consumption=idle }
        // Exercise the actual persisted legacy JSON shape, including absent review fields.
        var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(retained)) as! [String:Any]
        json["startedAt"]=Date().addingTimeInterval(-Double(days)*86400).timeIntervalSinceReferenceDate
        json.removeValue(forKey:"stateReviewRequired")
        let old=try JSONDecoder().decode(WaterSession.self,from:JSONSerialization.data(withJSONObject:json))
        s.current=old;r.replies=[idle,ack]
        let coldLaunch=try WaterController(transport:r,provider:p,store:s)
        try await coldLaunch.startNext(config:config)
        #expect(s.history == [old] && old.receipt == nil)
        #expect(coldLaunch.session?.stage == .active && coldLaunch.session!.startedAt > old.startedAt)
        #expect(p.calls == 1 && p.settlements == 0)
        let reopened=try WaterController(transport:r,provider:p,store:s)
        #expect(reopened.archivedSessions == [old] && reopened.session?.stage == .active)
    }
}
