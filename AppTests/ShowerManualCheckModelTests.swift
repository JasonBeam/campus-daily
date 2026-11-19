import XCTest
import Core
@testable import XiaoRiChang

/// Plan item 20: the manual 核对 on 连接检查 (`ShowerModel.inspectBluetooth`). It reads the
/// controller's number and nothing else: one probe, the link closed, no start, nothing sent to the
/// platform. A matching number sets the binding's matched marker, under the same guard a start uses
/// (the same binding identity, no start taken back since). On fakes only.
@MainActor
final class ShowerManualCheckModelTests: XCTestCase {
    var link: InspectableControllerLink!
    var http: CountingShowerHTTP!
    var store: ScriptedStore!

    override func setUp() async throws {
        link = InspectableControllerLink()
        http = CountingShowerHTTP()
        store = ScriptedStore()
    }

    func model(binding: ShowerBinding = Fixture.binding) async throws -> ShowerModel {
        try StoredShowerVault(store:store).saveBinding(binding)
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:http, laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:link, leaseFile:nil,
                                      applicationSupport:try Fixture.supportWithProfile(), sharedDidChange:{})
        let model = ShowerModel(services:services, reminders:.sample(defaults:services.defaults), activities:nil,
                                gate:LiveShowerGate(), bluetoothAccess:FakeBluetoothAccess())
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded && model.engine != nil }
        return model
    }

    var storedMarker: Date? { ((try? StoredShowerVault(store:store).binding()) ?? nil)?.matchedAt }

    /// Read-only: one scan, one probe, the link closed; no start, no platform request.
    func assertReadOnly(_ shower: ShowerModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(link.inspects, 1, "one scan", file:file, line:line)
        XCTAssertEqual(link.connects, 1, file:file, line:line)
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand], "only the identity probe", file:file, line:line)
        XCTAssertGreaterThanOrEqual(link.disconnects, 1, "the link is closed", file:file, line:line)
        XCTAssertEqual(http.sent, 0, "no authorize, no settle", file:file, line:line)
        XCTAssertEqual(shower.state.phase, .idle, file:file, line:line)
        XCTAssertTrue(shower.state.canStart, file:file, line:line)
        XCTAssertNil(shower.startSlot, "no start", file:file, line:line)
        XCTAssertFalse(shower.page.starting, file:file, line:line)
        XCTAssertFalse(shower.inspecting, file:file, line:line)
    }

    func testAMatchingNumberSetsTheMarkerAndStartsNothing() async throws {
        link.replies = [FakeFramesApp.idle]
        let shower = try await model()
        XCTAssertNil(storedMarker)
        await shower.inspectBluetooth()
        XCTAssertEqual(shower.inspectionOutcome, .verified)
        assertReadOnly(shower)
        XCTAssertNotNil(storedMarker, "kept")
        XCTAssertNotNil(shower.binding?.matchedAt, "and shown")
        await pause(50)
        XCTAssertEqual(http.sent, 0, "nothing ran after it either")
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand])
    }

    func testAnotherMachineOrAnInUseControllerSetsNothing() async throws {
        let other = Data([0x55, 0x99, 0x88, 0x77, 0x66] + [UInt8](repeating: 0, count: 15))
        for (reply, outcome) in [(other, ShowerModel.InspectionOutcome.otherMachine), (FakeFramesApp.active, .inUse)] {
            try await setUp()
            link.replies = [reply]
            let shower = try await model()
            await shower.inspectBluetooth()
            XCTAssertEqual(shower.inspectionOutcome, outcome)
            assertReadOnly(shower)
            XCTAssertNil(storedMarker, "\(outcome)")
            XCTAssertNil(shower.binding?.matchedAt)
        }
    }

    /// The same binding, but a start taken back while the probe was out (the app sent to the
    /// background): the generation guard leaves the marker unset.
    func testATakenBackGenerationWritesNoMarker() async throws {
        link.holdExchange = true
        let shower = try await model()
        let check = Task { await shower.inspectBluetooth() }
        await waitUntil { link.isHolding }
        XCTAssertTrue(link.isHolding)
        shower.sceneChanged(.background)
        link.release(FakeFramesApp.idle)
        await check.value
        XCTAssertEqual(shower.inspectionOutcome, .verified, "the number did match")
        assertReadOnly(shower)
        XCTAssertNil(storedMarker)
        XCTAssertNil(shower.binding?.matchedAt)
    }

    /// The binding went (an account switch) while the probe was out: nothing written for anyone.
    func testABindingGoneDuringTheProbeWritesNoMarker() async throws {
        link.holdExchange = true
        let shower = try await model()
        let check = Task { await shower.inspectBluetooth() }
        await waitUntil { link.isHolding }
        _ = shower.clearBindingForAccountSwitch()
        link.release(FakeFramesApp.idle)
        await check.value
        XCTAssertEqual(http.sent, 0)
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand])
        XCTAssertNil(try StoredShowerVault(store:store).binding())
        XCTAssertNil(shower.binding)
    }

    /// Another person's binding on the same controller is not this check's: saved in place of
    /// the checked one underneath the model (same machine, other identity), it is left unmarked.
    func testAnotherIdentityOnTheSameControllerIsNotMarked() async throws {
        link.holdExchange = true
        let shower = try await model()
        let check = Task { await shower.inspectBluetooth() }
        await waitUntil { link.isHolding }
        try StoredShowerVault(store:store).saveBinding(
            ShowerBinding(studentId:"S-2", schoolId:"1", machineId:"11223344", roomId:"R-2", roomLabel:"99栋 992"))
        link.release(FakeFramesApp.idle)
        await check.value
        XCTAssertEqual(http.sent, 0)
        XCTAssertNil(storedMarker)
    }

    func testAnEarlierMarkerIsKept() async throws {
        var marked = Fixture.binding
        let first = Date(timeIntervalSince1970:1_800_000_000)
        marked.matchedAt = first
        link.replies = [FakeFramesApp.idle]
        let shower = try await model(binding:marked)
        await shower.inspectBluetooth()
        XCTAssertEqual(shower.inspectionOutcome, .verified)
        assertReadOnly(shower)
        XCTAssertEqual(storedMarker, first)
    }

    /// The rebind the check would race is refused while it runs (`ShowerBinding.checkMayReplace`).
    func testARebindIsRefusedWhileTheCheckRuns() async throws {
        link.holdExchange = true
        let shower = try await model()
        let check = Task { await shower.inspectBluetooth() }
        await waitUntil { link.isHolding }
        XCTAssertThrowsError(try shower.saveBinding(
            ShowerBinding(studentId:"S-2", schoolId:"1", machineId:"11223344", roomId:"R-2", roomLabel:"99栋 992")))
        link.release(FakeFramesApp.idle)
        await check.value
        XCTAssertNotNil(storedMarker, "the checked binding, unchanged, is marked")
    }
}

/// `ScriptedControllerLink` that also answers the 连接检查 scan (`ShowerInspectingTransport`):
/// `nearby` controllers, `inspects` counted.
final class InspectableControllerLink: ShowerInspectingTransport, @unchecked Sendable {
    let base = ScriptedControllerLink()
    private let lock = NSLock()
    private var _inspects = 0
    var nearby = 1
    var inspects: Int { lock.withLock { _inspects } }

    func inspect(bleName: String, remembered: String?) async throws -> Int {
        lock.withLock { _inspects += 1 }
        return nearby
    }
    func connect(bleName: String, machineID: String, required: String?, preferred: String?) async throws -> String {
        try await base.connect(bleName:bleName, machineID:machineID, required:required, preferred:preferred)
    }
    func exchange(_ command: Data) async throws -> Data { try await base.exchange(command) }
    func disconnect() async { await base.disconnect() }

    var writes: [Data] { base.writes }
    var connects: Int { base.connects }
    var disconnects: Int { base.disconnects }
    var isHolding: Bool { base.isHolding }
    var replies: [Data] { get { base.replies } set { base.replies = newValue } }
    var holdExchange: Bool { get { base.holdExchange } set { base.holdExchange = newValue } }
    func release(_ frame: Data) { base.release(frame) }
}
