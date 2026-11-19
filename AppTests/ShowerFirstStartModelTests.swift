import XCTest
import Core
@testable import XiaoRiChang

/// The first 开始洗澡 and every explicit start after it (`ShowerStartIntent`): one start per tap,
/// the explainer before Bluetooth is first asked for, and nothing sent for a tap whose account,
/// dorm or moment has gone. On fake stores, a scripted controller and a platform that counts its
/// requests: nothing real is read or sent.
@MainActor
final class ShowerFirstStartModelTests: XCTestCase {
    var link: ScriptedControllerLink!
    var http: CountingShowerHTTP!
    var access: FakeBluetoothAccess!
    var store: ScriptedStore!

    override func setUp() async throws {
        link = ScriptedControllerLink()
        http = CountingShowerHTTP()
        access = FakeBluetoothAccess()
        store = ScriptedStore()
    }

    func model(binding: ShowerBinding = Fixture.binding, record: ShowerState? = nil) async throws -> ShowerModel {
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(binding)
        if let record { try vault.saveShowerState(record) }
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:http, laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:link, leaseFile:nil,
                                      applicationSupport:try Fixture.supportWithProfile(), sharedDidChange:{})
        let model = ShowerModel(services:services, reminders:.sample(defaults:services.defaults), activities:nil,
                                gate:LiveShowerGate(), bluetoothAccess:access)
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded && model.engine != nil }
        return model
    }

    /// Lets every task the taps made run to the end.
    func settle(_ shower: ShowerModel) async {
        await pause(50)
        await waitUntil { !shower.busy && shower.startSlot == nil }
        await pause(20)
    }

    var matched: ShowerBinding {
        var b = Fixture.binding
        b.matchedAt = Date(timeIntervalSince1970:1_800_000_000)
        b.peripheralID = "P"
        return b
    }

    // MARK: 12. The explainer

    func testNeverAskedShowsTheExplainerAndNothingElse() async throws {
        access.authorization = .notDetermined
        let shower = try await model()
        XCTAssertEqual(shower.tapStart(.page), .explainer)
        XCTAssertNotNil(shower.explainerIntent)
        XCTAssertEqual(access.requests, 0, "no system alert before 好，开始")
        await pause(50)
        XCTAssertEqual(link.connects, 0)

        shower.cancelExplainer(shower.explainerIntent!.id)
        XCTAssertNil(shower.startSlot)
        XCTAssertNil(shower.explainerIntent)
        await pause(50)
        XCTAssertEqual(access.requests, 0)
        XCTAssertEqual(link.connects, 0)
        XCTAssertEqual(http.sent, 0)
        XCTAssertFalse(shower.page.starting, "the button is back as it was")
    }

    /// 13: 好，开始 asks once; allowed, exactly one start runs, with the probe first.
    func testConfirmAsksOnceThenStartsOnce() async throws {
        access.authorization = .notDetermined
        access.answer = .allowed
        link.replies = [FakeFramesApp.idle]
        let shower = try await model()
        shower.tapStart(.page)
        let id = shower.explainerIntent!.id
        shower.confirmExplainer(id)
        shower.confirmExplainer(id)
        shower.cancelExplainer(id)  // the sheet going down after the confirm is not a cancel
        await settle(shower)
        XCTAssertEqual(access.requests, 1)
        XCTAssertEqual(link.connects, 1)
        XCTAssertEqual(link.writes.first, ShowerFrames.probeCommand)
        XCTAssertEqual(http.sent, 1, "one authorize")
    }

    // MARK: 14. The permission answer comes back to a start that has gone

    func testAnAnswerAfterTheStartWasTakenBackStartsNothing() async throws {
        let takeBacks: [(String, (ShowerModel) throws -> Void)] = [
            ("sign-out", { $0.holdForSignOut() }),
            ("account switch", { _ = $0.clearBindingForAccountSwitch() }),
            ("rebind", { try $0.saveBinding(ShowerBinding(studentId:"S-2", schoolId:"1", machineId:"11223344", roomId:"R-2", roomLabel:"99栋 992")) }),
            ("background", { $0.sceneChanged(.background) }),
        ]
        for (label, takeBack) in takeBacks {
            setUpFakes(notDetermined:true)
            let shower = try await model()
            shower.tapStart(.page)
            let id = shower.explainerIntent!.id
            shower.confirmExplainer(id)
            await waitUntil { self.access.holding }
            try takeBack(shower)
            access.release(.allowed)
            await settle(shower)
            XCTAssertEqual(link.connects, 0, label)
            XCTAssertEqual(http.sent, 0, label)
            XCTAssertNil(shower.startSlot, label)
        }
    }

    /// The system alert makes the app inactive: the start waits for it and goes on.
    func testTheAlertsInactiveDoesNotCancel() async throws {
        setUpFakes(notDetermined:true)
        link.replies = [FakeFramesApp.idle]
        let shower = try await model()
        shower.tapStart(.page)
        shower.confirmExplainer(shower.explainerIntent!.id)
        await waitUntil { self.access.holding }
        shower.sceneChanged(.inactive)
        shower.sceneChanged(.active)
        access.release(.allowed)
        await settle(shower)
        XCTAssertEqual(link.connects, 1)
        XCTAssertEqual(http.sent, 1)
    }

    // MARK: 15 / 24. Denied

    func testDeniedSaysWhyAndStartsNothing() async throws {
        access.authorization = .denied
        let shower = try await model()
        XCTAssertEqual(shower.tapStart(.page), .refused)
        XCTAssertNil(shower.startSlot, "no start kept")
        XCTAssertEqual(shower.page.checkFailure, .noPermission)
        await pause(50)
        XCTAssertEqual(link.connects, 0)
        XCTAssertEqual(access.requests, 0)

        // Back from Settings with Bluetooth allowed: nothing starts by itself.
        access.authorization = .allowed
        shower.sceneChanged(.active)
        await pause(50)
        XCTAssertEqual(link.connects, 0)
        XCTAssertNil(shower.page.checkFailure, "the stale line goes")
        // The next tap reads the permission again.
        link.replies = [FakeFramesApp.idle]
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:true))
        await settle(shower)
        XCTAssertEqual(link.connects, 1)
    }

    /// Denied in the alert: the same line, nothing connects.
    func testDeniedInTheAlert() async throws {
        setUpFakes(notDetermined:true)
        let shower = try await model()
        shower.tapStart(.page)
        shower.confirmExplainer(shower.explainerIntent!.id)
        await waitUntil { self.access.holding }
        access.release(.denied)
        await settle(shower)
        XCTAssertEqual(shower.page.checkFailure, .noPermission)
        XCTAssertEqual(link.connects, 0)
        XCTAssertNil(shower.startSlot)
    }

    /// Off after the permission was given: the first check says 蓝牙关着, as a line.
    func testBluetoothOffAfterAllowedIsTheOffLine() async throws {
        link.connectError = .bluetoothOff
        let shower = try await model()
        shower.tapStart(.page)
        await settle(shower)
        XCTAssertEqual(shower.page.checkFailure, .off)
        XCTAssertFalse(shower.page.presented)
        XCTAssertTrue(shower.mayStart, "tap again")
        XCTAssertEqual(http.sent, 0)
    }

    // MARK: 16 / 23. One start for many taps

    func testDuplicateTapsMakeOneStart() async throws {
        setUpFakes(notDetermined:true)
        link.replies = [FakeFramesApp.idle]
        let shower = try await model()
        XCTAssertEqual(shower.tapStart(.home), .explainer)
        XCTAssertEqual(shower.tapStart(.page), .joined)
        XCTAssertEqual(shower.tapStart(.page, showingPage:true), .joined)
        let id = shower.explainerIntent!.id
        shower.confirmExplainer(id)
        shower.confirmExplainer(id)
        await waitUntil { self.access.holding }
        let siri = await shortcutRefusal(shower)
        XCTAssertNotNil(siri, "Siri joins nothing and starts nothing while a start waits")
        access.release(.allowed)
        shower.permissionReturned(id, .allowed)  // a second answer for the same start
        await settle(shower)
        XCTAssertEqual(access.requests, 1)
        XCTAssertEqual(link.connects, 1)
        XCTAssertEqual(http.sent, 1)
    }

    // MARK: 17. Siri and Shortcuts

    func shortcutRefusal(_ shower: ShowerModel, clear: Bool = false) async -> String? {
        do { _ = try await shower.startFromShortcut(clear:clear); return nil }
        catch let failure as ShowerActionFailure { return failure.message }
        catch { return "\(error)" }
    }

    func testShortcutsNeverAskOrExplain() async throws {
        access.authorization = .notDetermined
        let shower = try await model()
        let warm = await shortcutRefusal(shower)
        XCTAssertEqual(warm, "第一次洗澡要在校日常里点「开始洗澡」，先核对一下水控。")
        let clear = await shortcutRefusal(shower, clear:true)
        XCTAssertEqual(clear, "首次洗澡需在校日常中点「开始洗澡」以核对水控")
        XCTAssertNil(shower.explainerIntent)
        access.authorization = .denied
        let denied = await shortcutRefusal(shower)
        XCTAssertEqual(denied, FirstCheckFailure.noPermission.text(clear:false))
        XCTAssertEqual(access.requests, 0)
        XCTAssertEqual(link.connects, 0)
        XCTAssertNil(shower.startSlot)
    }

    // MARK: 18 / 25. 退出登录 while the number is read

    func testSignOutDuringTheProbeSendsNothing() async throws {
        link.holdExchange = true
        let shower = try await model()
        shower.tapStart(.page)
        await waitUntil { self.link.isHolding }
        shower.holdForSignOut()
        link.release(FakeFramesApp.idle)
        await settle(shower)
        XCTAssertEqual(http.sent, 0, "authorize 0")
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand], "no authorization written")
        // The engine's "sent" mark came before the permit refused: no page, no 找到了, and the
        // withdrawn start is cleared off the screen once the engine is free (`.dismissRecord`).
        XCTAssertFalse(shower.page.presented, "no failure face")
        XCTAssertEqual(shower.page.checkPassed, 0, "no 找到了")
        XCTAssertFalse(shower.checkToastShown)
        await waitUntil { shower.state.phase == .idle }
        XCTAssertEqual(shower.state.phase, .idle)
        XCTAssertNil(try StoredShowerVault(store:store).showerState()?.failure)
    }

    func testSignOutDuringAShortcutStartSendsNothing() async throws {
        link.holdExchange = true
        let shower = try await model(binding:matched)
        let siri = Task { await self.shortcutRefusal(shower) }
        await waitUntil { self.link.isHolding }
        shower.holdForSignOut()
        link.release(FakeFramesApp.idle)
        _ = await siri.value
        await settle(shower)
        XCTAssertEqual(http.sent, 0)
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand])
    }

    /// The page's 开始下一次洗澡: the old record is not kept aside, nothing is asked or settled.
    func testSignOutDuringANextUseProbeSendsNothing() async throws {
        var stopped = Fixture.running
        stopped.stateReviewRequired = true
        stopped.authorizeSent = true
        link.holdExchange = true
        let shower = try await model(binding:matched, record:stopped)
        XCTAssertTrue(shower.mayStartNext)
        shower.tapStart(.page, kind:.next)
        await waitUntil { self.link.isHolding }
        shower.holdForSignOut()
        link.release(FakeFramesApp.idle)
        await settle(shower)
        XCTAssertEqual(http.sent, 0, "authorize 0, settle 0")
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand])
        XCTAssertEqual(try StoredShowerVault(store:store).retainedShowers(), [], "not kept aside")
    }

    // MARK: 19 / 26. The matched marker

    func testTheMarkerIsSetByAMatchedStartAndNeverSkipsTheProbe() async throws {
        var remembered = Fixture.binding
        remembered.peripheralID = "P"
        link.replies = [FakeFramesApp.idle]
        let shower = try await model(binding:remembered)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:true), "a remembered controller is not a match")
        await settle(shower)
        XCTAssertNotNil(shower.binding?.matchedAt)
        XCTAssertNotNil(try StoredShowerVault(store:store).binding()?.matchedAt)
        XCTAssertEqual(link.writes.first, ShowerFrames.probeCommand)
    }

    /// The account changed while the request was out: its answer is not this person's match.
    func testALateResultIsNotWrittenForAnotherAccount() async throws {
        let held = HeldHTTP()
        let shower = try await modelWithHeldPlatform(held)
        link.replies = [FakeFramesApp.idle]
        shower.tapStart(.page)
        let reached = await held.reached()
        XCTAssertTrue(reached)
        _ = shower.clearBindingForAccountSwitch()
        held.release()
        await settle(shower)
        XCTAssertNil(try StoredShowerVault(store:store).binding()?.matchedAt)
        XCTAssertNil(shower.binding?.matchedAt)
    }

    func modelWithHeldPlatform(_ held: HeldHTTP) async throws -> ShowerModel {
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:held, laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:link, leaseFile:nil,
                                      applicationSupport:try Fixture.supportWithProfile(), sharedDidChange:{})
        let model = ShowerModel(services:services, reminders:.sample(defaults:services.defaults), activities:nil,
                                gate:LiveShowerGate(), bluetoothAccess:access)
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded && model.engine != nil }
        return model
    }

    // MARK: 21 / 22. The start's identity is the tap's

    func testARebindBeforeTheStartRunsStartsNothing() async throws {
        link.replies = [FakeFramesApp.idle]
        let shower = try await model()
        shower.tapStart(.page)
        // Same turn: the start's task has not run yet.
        try shower.saveBinding(ShowerBinding(studentId:"S-2", schoolId:"1", machineId:"11223344", roomId:"R-2", roomLabel:"99栋 992"))
        await settle(shower)
        XCTAssertEqual(link.connects, 0)
        XCTAssertEqual(http.sent, 0)
    }

    func testARebindAfterThePermissionAnswerStartsNothing() async throws {
        setUpFakes(notDetermined:true)
        let shower = try await model()
        shower.tapStart(.page)
        let id = shower.explainerIntent!.id
        shower.confirmExplainer(id)
        shower.permissionReturned(id, .allowed)
        try shower.saveBinding(ShowerBinding(studentId:"S-2", schoolId:"1", machineId:"11223344", roomId:"R-2", roomLabel:"99栋 992"))
        access.release(.allowed)
        await settle(shower)
        XCTAssertEqual(link.connects, 0)
        XCTAssertEqual(http.sent, 0)
    }

    // MARK: Review item 4: a stale start's return leaves the newer one alone

    /// A queued, taken back, B waiting on its explainer: A's return clears neither B's slot nor
    /// anything B shows.
    func testAStaleStartsReturnLeavesAWaitingStartAlone() async throws {
        let shower = try await model()
        shower.tapStart(.page)
        let a = shower.startSlot?.id
        shower.sceneChanged(.background)
        shower.sceneChanged(.active)
        access.authorization = .notDetermined
        XCTAssertEqual(shower.tapStart(.page), .explainer)
        let b = shower.startSlot?.id
        XCTAssertNotEqual(a, b)
        await pause(80)  // A's task runs and returns
        XCTAssertEqual(shower.startSlot?.id, b)
        XCTAssertEqual(shower.startSlot?.phase, .awaitingConfirm)
        XCTAssertEqual(link.connects, 0)
    }

    /// A queued, taken back, B checking: A's return does not end B's check on the page.
    func testAStaleStartsReturnLeavesACheckingStartAlone() async throws {
        link.holdExchange = true
        let shower = try await model()
        shower.tapStart(.page)
        let a = shower.startSlot?.id
        shower.sceneChanged(.background)
        shower.sceneChanged(.active)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:true))
        let b = shower.startSlot?.id
        XCTAssertNotEqual(a, b)
        await waitUntil { self.link.isHolding }
        await pause(50)
        XCTAssertEqual(shower.startSlot?.id, b, "B's slot")
        XCTAssertTrue(shower.page.starting, "B is still starting on the page")
        XCTAssertTrue(shower.page.firstCheck)
        XCTAssertTrue(shower.page.checking)
        XCTAssertEqual(shower.startTaskID, b)
        link.release(FakeFramesApp.active)
        await settle(shower)
        XCTAssertEqual(link.connects, 1, "only B connected")
        XCTAssertEqual(shower.page.checkFailure, .inUse)
        XCTAssertEqual(http.sent, 0)
    }

    // MARK: The first check on the page

    func testAFirstCheckFailureIsTheLineUnderTheButton() async throws {
        link.replies = [Data([0x55, 0x99, 0x88, 0x77, 0x66] + [UInt8](repeating: 0, count: 15))]
        let shower = try await model()
        XCTAssertEqual(shower.tapStart(.home), .started(firstCheck:true))
        XCTAssertFalse(shower.page.presented, "the check shows on the 热水洗澡 screen")
        XCTAssertTrue(shower.page.checking)
        await settle(shower)
        XCTAssertEqual(shower.page.checkFailure, .otherMachine)
        XCTAssertFalse(shower.page.presented)
        XCTAssertTrue(shower.mayStart)
        XCTAssertNil(shower.binding?.matchedAt)
        XCTAssertEqual(http.sent, 0)
    }

    func testAMatchedBindingStartsAsToday() async throws {
        link.replies = [FakeFramesApp.idle]
        let shower = try await model(binding:matched)
        XCTAssertEqual(shower.tapStart(.home), .started(firstCheck:false))
        XCTAssertTrue(shower.page.presented)
        XCTAssertFalse(shower.page.checking)
        await settle(shower)
        XCTAssertEqual(link.writes.first, ShowerFrames.probeCommand)
    }

    // MARK: Helpers

    func setUpFakes(notDetermined: Bool) {
        link = ScriptedControllerLink()
        http = CountingShowerHTTP()
        access = FakeBluetoothAccess()
        store = ScriptedStore()
        if notDetermined {
            access.authorization = .notDetermined
            access.hold = true
        }
    }
}

/// The app's Bluetooth permission, scripted: `request()` counts, and with `hold` waits for `release`.
@MainActor final class FakeBluetoothAccess: BluetoothAccess {
    var authorization: BluetoothAuthorization = .allowed
    var answer: BluetoothAuthorization = .allowed
    var hold = false
    private(set) var requests = 0
    private var held: CheckedContinuation<BluetoothAuthorization, Never>?
    var holding: Bool { held != nil }

    func request() async -> BluetoothAuthorization {
        requests += 1
        if hold { return await withCheckedContinuation { held = $0 } }
        authorization = answer
        return answer
    }

    func release(_ answer: BluetoothAuthorization) {
        authorization = answer
        let c = held
        held = nil
        c?.resume(returning:answer)
    }
}

/// The hot-water platform answering every request offline at once (nothing confirmed), counting them.
final class CountingShowerHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent = 0
    var sent: Int { lock.withLock { _sent } }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _sent += 1 }
        throw ServiceError.offline
    }
}
