//
//  ShowerBalanceGateModelTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
import CryptoKit
import Core
@testable import XiaoRiChang

/// 开始洗澡 below a zero balance (`ShowerBalanceGate`), on the live model: every way in (home, the
/// 热水洗澡 screen, 清爽's dock, 再试一次, 开始下一次洗澡, the first check, Siri) is refused before
/// anything is asked for or sent; zero, a positive balance and no balance start as today; a
/// shower already on is never touched; debt allowed on this phone lets −0.50 start, and taking
/// that back takes back a start that hasn't sent its authorize request. On fake stores, a
/// scripted controller and a platform that counts its requests: nothing real is read or sent.
@MainActor
final class ShowerBalanceGateModelTests: XCTestCase {
    var link: ScriptedControllerLink!
    var http: CountingShowerHTTP!
    var access: FakeBluetoothAccess!
    var store: ScriptedStore!

    override func setUp() async throws { fresh() }

    func fresh() {
        link = ScriptedControllerLink()
        http = CountingShowerHTTP()
        access = FakeBluetoothAccess()
        store = ScriptedStore()
    }

    /// −0.50, read now.
    static let owed = ShowerBalance(amount:Money(yuanString:"-0.50")!, readAt:Date())
    static func balance(fen: Int) -> ShowerBalance { ShowerBalance(amount:Money(fen:fen), readAt:Date()) }
    /// What each theme says for `owed` (copy v2 §1).
    static let warmLine = "校园卡欠了 ¥0.50，充上再来洗。"
    static let clearLine = "校园卡余额 -¥0.50；请充值后再开始洗澡"

    /// A binding whose controller a start has matched already: a start goes straight to the page.
    var matched: ShowerBinding {
        var b = Fixture.binding
        b.matchedAt = Date(timeIntervalSince1970:1_800_000_000)
        b.peripheralID = "P"
        return b
    }

    /// A shower stopped on the controller (开始下一次洗澡 is offered).
    var stopped: ShowerState {
        var s = Fixture.running
        s.stateReviewRequired = true
        s.authorizeSent = true
        return s
    }

    /// `allowsDebt`: debt allowed on this phone before anything else happens.
    func model(binding: ShowerBinding? = nil, record: ShowerState? = nil, allowsDebt: Bool = false,
               platform: (any HTTPClient)? = nil) async throws -> ShowerModel {
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(binding ?? matched)
        if let record { try vault.saveShowerState(record) }
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:platform ?? http, laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:link, leaseFile:nil,
                                      applicationSupport:try Fixture.supportWithProfile(), sharedDidChange:{})
        let model = ShowerModel(services:services, reminders:.sample(defaults:services.defaults), activities:nil,
                                gate:LiveShowerGate(), bluetoothAccess:access)
        if allowsDebt { model.setAllowsDebt(true) }
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded && model.engine != nil }
        return model
    }

    func settle(_ shower: ShowerModel) async {
        await pause(50)
        await waitUntil { !shower.busy && shower.startSlot == nil }
        await pause(20)
    }

    func shortcutRefusal(_ shower: ShowerModel, clear: Bool = false) async -> String? {
        do { _ = try await shower.startFromShortcut(clear:clear); return nil }
        catch let failure as ShowerActionFailure { return failure.message }
        catch { return "\(error)" }
    }

    /// Nothing reached the controller or the platform, nothing was asked, no start is held.
    func assertNothingSent(_ shower: ShowerModel, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(link.connects, 0, "\(label): no Bluetooth connect", file:file, line:line)
        XCTAssertEqual(link.writes, [], "\(label): nothing written to the controller", file:file, line:line)
        XCTAssertEqual(http.sent, 0, "\(label): no authorize request", file:file, line:line)
        XCTAssertEqual(access.requests, 0, "\(label): no Bluetooth permission asked", file:file, line:line)
        XCTAssertNil(shower.startSlot, "\(label): no start held", file:file, line:line)
    }

    // MARK: The gate on the model

    func testMinusFiftyFenGreysOutTheStartWithTheBalanceReason() async throws {
        let shower = try await model()
        XCTAssertTrue(shower.mayStart, "before the balance is known")
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.balance, Self.owed)
        XCTAssertTrue(shower.balanceBlocks)
        XCTAssertFalse(shower.mayStart)
        XCTAssertEqual(shower.startBlock, .balanceNegative)
    }

    /// Siri and Shortcuts can't see the page: the refusal says what the card owes.
    func testTheRefusalTextSaysTheBalance() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.startRefusalText, Self.warmLine)
    }

    /// The other reasons say what is going on first.
    func testAnAccountReasonComesBeforeTheBalance() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        shower.holdForSignOut()
        XCTAssertEqual(shower.startBlock, .accountChanged)
    }

    // MARK: Every way in, refused before anything is sent

    /// 暖橙 home's capsule (`HomeView.tap(.start)` → `tapStart(.home)`).
    func testHomeStartSendsNothing() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.home), .notAllowed)
        await settle(shower)
        assertNothingSent(shower, "home")
        XCTAssertFalse(shower.page.presented, "no starting page")
        XCTAssertFalse(shower.page.starting)
    }

    /// 暖橙's 热水洗澡 screen (`ShowerDetail`: `tapStart(.page, showingPage:true)`).
    func testDetailStartSendsNothing() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.page, showingPage:true), .notAllowed)
        await settle(shower)
        assertNothingSent(shower, "detail")
        XCTAssertFalse(shower.page.starting)
    }

    /// 清爽's dock with no session (`ClearShowerDock.start`), on the page already up.
    func testClearDockStartSendsNothing() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.page), .notAllowed)
        await settle(shower)
        assertNothingSent(shower, "clear dock")
        XCTAssertFalse(shower.page.starting)
    }

    /// 再试一次 on the connect-failed face (both themes' retry is `tapStart(.retry)`).
    func testRetrySendsNothing() async throws {
        link.connectError = .notFound
        let shower = try await model()
        XCTAssertEqual(shower.tapStart(.page, showingPage:true), .started(firstCheck:false))
        await settle(shower)
        XCTAssertTrue(shower.page.mayRetry, "precondition: the face offers 再试一次")
        XCTAssertEqual(link.connects, 1)
        link.connectError = nil
        link.replies = [FakeFramesApp.idle]

        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.retry), .notAllowed)
        await settle(shower)
        XCTAssertEqual(link.connects, 1, "no second connect")
        XCTAssertEqual(http.sent, 0)
        XCTAssertNil(shower.startSlot)
        XCTAssertFalse(shower.page.starting, "the retry doesn't spin")
    }

    /// 开始下一次洗澡 over a stopped shower: refused at the tap and in `startNext` itself.
    func testNextSendsNothing() async throws {
        let shower = try await model(record:stopped)
        XCTAssertTrue(shower.mayStartNext, "precondition: offered without a balance")
        shower.noteBalance(Self.owed)
        XCTAssertFalse(shower.mayStartNext)
        XCTAssertEqual(shower.tapStart(.page, kind:.next), .notAllowed)
        await settle(shower)
        assertNothingSent(shower, "next tap")

        let intent = ShowerStartIntent(entry:.page, kind:.next, binding:matched, generation:shower.startGeneration,
                                       firstCheck:false, phase:.starting, showingPage:false)
        let went = await shower.startNext(intent)
        XCTAssertFalse(went)
        XCTAssertEqual(link.connects, 0)
        XCTAssertEqual(http.sent, 0)
    }

    /// The first check, never asked for Bluetooth: no explainer and no system alert.
    func testFirstCheckNeverExplainsOrAsks() async throws {
        access.authorization = .notDetermined
        let shower = try await model(binding:Fixture.binding)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.page), .notAllowed)
        XCTAssertNil(shower.explainerIntent)
        await settle(shower)
        assertNothingSent(shower, "first check")
    }

    /// The first check, Bluetooth allowed: nothing connects for the probe either.
    func testFirstCheckWithBluetoothAllowedSendsNothing() async throws {
        let shower = try await model(binding:Fixture.binding)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.home), .notAllowed)
        await settle(shower)
        assertNothingSent(shower, "first check, allowed")
        XCTAssertFalse(shower.page.checking)
    }

    /// The explainer was up before the balance came back below zero: once the alert is answered,
    /// the start is checked again before the engine and nothing connects.
    func testAFirstCheckWaitingOnTheAlertStartsNothingOnceTheBalanceIsBelowZero() async throws {
        access.authorization = .notDetermined
        access.hold = true
        let shower = try await model(binding:Fixture.binding)
        XCTAssertEqual(shower.tapStart(.page), .explainer)
        shower.confirmExplainer(shower.explainerIntent!.id)
        await waitUntil { self.access.holding }
        shower.noteBalance(Self.owed)
        access.release(.allowed)
        await settle(shower)
        XCTAssertEqual(link.connects, 0)
        XCTAssertEqual(http.sent, 0)
    }

    /// Siri / Shortcuts (`StartShowerIntent` → `startFromShortcut`), both themes' words.
    func testSiriSaysTheBalanceAndSendsNothing() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        let warm = await shortcutRefusal(shower)
        let clear = await shortcutRefusal(shower, clear:true)
        XCTAssertEqual(warm, Self.warmLine)
        XCTAssertEqual(clear, Self.clearLine)
        assertNothingSent(shower, "Siri")
    }

    /// Siri says the balance before anything about Bluetooth.
    func testSiriSaysTheBalanceBeforeBluetooth() async throws {
        access.authorization = .notDetermined
        let shower = try await model()
        shower.noteBalance(Self.owed)
        let text = await shortcutRefusal(shower)
        XCTAssertEqual(text, Self.warmLine)
        assertNothingSent(shower, "Siri, never asked")
    }

    /// Siri over a stopped shower is 开始下一次洗澡: refused for the balance, and says so (not
    /// the record's words: a shower that is over doesn't stop a next one).
    func testSiriNextSaysTheBalanceAndSendsNothing() async throws {
        let shower = try await model(record:stopped)
        shower.noteBalance(Self.owed)
        let text = await shortcutRefusal(shower)
        XCTAssertEqual(text, Self.warmLine)
        XCTAssertEqual(link.connects, 0)
        XCTAssertEqual(http.sent, 0)
    }

    // MARK: Which reason is said

    /// Over a stopped shower the refusal is the balance's, not `state.canStart`'s.
    func testTheNextRefusalTextIsTheBalance() async throws {
        let shower = try await model(record:stopped)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.startRefusalText, Self.warmLine)
        XCTAssertEqual(shower.nextBlock, .balanceNegative, "the line under 开始下一次洗澡")
    }

    /// Nothing below zero: no line under 开始下一次洗澡.
    func testNoNextBlockWithoutTheBalance() async throws {
        let shower = try await model(record:stopped)
        XCTAssertNil(shower.nextBlock)
        shower.noteBalance(Self.balance(fen:0))
        XCTAssertNil(shower.nextBlock)
    }

    /// Siri doesn't put the balance over the reasons that come first: the account's.
    func testSiriSaysTheAccountBeforeTheBalance() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        shower.holdForSignOut()
        let text = await shortcutRefusal(shower)
        XCTAssertEqual(text, shower.startRefusalText)
        XCTAssertNotNil(text)
        XCTAssertFalse(text?.contains("欠") ?? true, text ?? "nil")
        XCTAssertTrue(text?.contains("学校账号") ?? false, text ?? "nil")
        XCTAssertEqual(link.connects, 0)
    }

    /// … and a shower still running (not over: over one, Siri's start is 开始下一次洗澡).
    func testSiriSaysTheUnsettledRecordBeforeTheBalance() async throws {
        let shower = try await model(record:Fixture.running)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.startBlock, .unsettled)
        let text = await shortcutRefusal(shower)
        XCTAssertNotNil(text)
        XCTAssertFalse(text?.contains("欠") ?? true, text ?? "nil")
        // (No connect assertion: the record's own check may reach the controller, as today.)
    }

    // MARK: The phrase (a made-up one and its digest)

    /// SHA-256 of the made-up phrase "ABC12" (not the real one), lowercase hex.
    static let fakeDigest = SHA256.hash(data:Data("ABC12".utf8)).map { String(format:"%02x", $0) }.joined()

    func testTheFakePhraseAllowsDebt() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        shower.tryUnlock(" abc 12 ", digest:Self.fakeDigest)
        XCTAssertTrue(shower.allowsDebt)
        XCTAssertTrue(shower.mayStart)
    }

    /// Wrong: nothing changes and nothing is said.
    func testAWrongPhraseIsSilent() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        for wrong in ["ABC1", "ABC123", "", "ＡＢＣ１２"] {
            shower.tryUnlock(wrong, digest:Self.fakeDigest)
            XCTAssertFalse(shower.allowsDebt, wrong)
            XCTAssertNil(shower.message, "\(wrong): no message")
        }
        XCTAssertFalse(ShowerStartOverrideStore(store:store).isOn)
    }

    /// Kept across a relaunch: a new model on the same Keychain starts with it on.
    func testDebtAllowedIsKeptAcrossARelaunch() async throws {
        let first = try await model()
        first.setAllowsDebt(true)
        XCTAssertTrue(ShowerStartOverrideStore(store:store).isOn, "written to the Keychain")
        let relaunched = try await model()
        XCTAssertTrue(relaunched.allowsDebt)
        relaunched.setAllowsDebt(false)
        let again = try await model()
        XCTAssertFalse(again.allowsDebt)
    }

    /// 重置校日常: the item goes, and the running model is back to the default at once.
    func testAResetTurnsItOffInTheRunningModel() async throws {
        let shower = try await model()
        shower.setAllowsDebt(true)
        XCTAssertTrue(shower.allowsDebt)
        try AppReset.clear(store:store, preferences:SampleDefaults(), preferencesDomain:"debt-reset", shared:nil, files:[])
        await shower.reloadAfterReset()
        XCTAssertFalse(shower.allowsDebt)
        shower.noteBalance(Self.owed)
        XCTAssertTrue(shower.balanceBlocks)
    }

    /// Debt allowed and stored; turning it off can't be stored (the Keychain refuses). It is off
    /// here at once and a −0.50 start reading the controller is taken back, and the caller is
    /// told it wasn't stored. Once the Keychain works again, turning it off sticks across a relaunch.
    func testATurnOffThatIsNotStoredSaysSo() async throws {
        link.holdExchange = true
        let shower = try await model(allowsDebt:true)
        XCTAssertTrue(ShowerStartOverrideStore(store:store).isOn)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        await waitUntil { self.link.isHolding }
        let permit = shower.startSlot?.permit
        store.refusing = [.showerStartMode]
        XCTAssertFalse(shower.setAllowsDebt(false), "the caller hears it wasn't stored")
        XCTAssertFalse(shower.allowsDebt, "off here at once")
        XCTAssertEqual(permit?.isOpen, false, "the start is taken back in the same step")
        link.release(FakeFramesApp.idle)
        await settle(shower)
        XCTAssertEqual(http.sent, 0, "no authorize request")
        store.refusing = []
        XCTAssertTrue(shower.setAllowsDebt(false), "stored on the retry")
        let relaunched = try await model()
        XCTAssertFalse(relaunched.allowsDebt, "off after a relaunch")
    }

    /// The page side of a switch-off the Keychain refused (`DebtShowerPending`): leaving the page
    /// or switching theme (a new visit) keeps the switch off with the line and its retry; a
    /// stored retry clears it, the next visit hasn't the group, and a relaunch reads it off.
    func testAnUnstoredSwitchOffSurvivesANewVisitUntilARetryIsStored() async throws {
        let shower = try await model(allowsDebt:true)
        let pending = DebtShowerPending()
        var visit = DebtShowerVisit()
        visit.appeared(on:shower.allowsDebt, pending:pending.unstored)
        store.refusing = [.showerStartMode]
        pending.turnOff(shower)
        XCTAssertTrue(pending.unstored)
        XCTAssertTrue(ShowerStartOverrideStore(store:store).isOn, "the item still says on")
        for page in ["re-entered", "other theme"] {
            var again = DebtShowerVisit()
            again.appeared(on:shower.allowsDebt, pending:pending.unstored)
            XCTAssertFalse(shower.allowsDebt, page)
            XCTAssertTrue(again.shows(pending:pending.unstored), "\(page): the group, with the line and retry")
            XCTAssertTrue(pending.unstored, page)
        }
        pending.turnOff(shower)
        XCTAssertTrue(pending.unstored, "a retry still refused")
        store.refusing = []
        pending.turnOff(shower)
        XCTAssertFalse(pending.unstored, "stored on the retry")
        var next = DebtShowerVisit()
        next.appeared(on:shower.allowsDebt, pending:pending.unstored)
        XCTAssertFalse(next.shows(pending:pending.unstored), "next visit: hidden")
        let relaunched = try await model()
        XCTAssertFalse(relaunched.allowsDebt, "off after a relaunch")
    }

    /// Turning it back on clears a pending switch-off.
    func testTurningBackOnClearsAPendingSwitchOff() async throws {
        let shower = try await model(allowsDebt:true)
        let pending = DebtShowerPending()
        store.refusing = [.showerStartMode]
        pending.turnOff(shower)
        XCTAssertTrue(pending.unstored)
        store.refusing = []
        XCTAssertTrue(shower.setAllowsDebt(true))
        pending.turnedOn()
        XCTAssertFalse(pending.unstored)
    }

    /// A reset that can't delete the item (it reports the failure): the running model is back
    /// to the default all the same; it doesn't read the old "allowed" back.
    func testAResetThatCantDeleteTheItemStillTurnsItOff() async throws {
        let shower = try await model(allowsDebt:true)
        store.refusing = [.showerStartMode]
        XCTAssertThrowsError(try AppReset.clear(store:store, preferences:SampleDefaults(), preferencesDomain:"debt-reset-fail",
                                                shared:nil, files:[]), "the reset reports it")
        await shower.reloadAfterReset()
        XCTAssertFalse(shower.allowsDebt)
        shower.noteBalance(Self.owed)
        XCTAssertTrue(shower.balanceBlocks)
    }

    // MARK: Allowed

    /// Zero, a positive balance and no balance start as today.
    func testZeroPositiveAndUnknownStart() async throws {
        let cases: [(String, ShowerBalance?)] = [("zero", Self.balance(fen:0)), ("positive", Self.balance(fen:1250)), ("unknown", nil)]
        for (label, value) in cases {
            fresh()
            link.replies = [FakeFramesApp.idle]
            let shower = try await model()
            shower.noteBalance(value)
            XCTAssertFalse(shower.balanceBlocks, label)
            XCTAssertTrue(shower.mayStart, label)
            XCTAssertNil(shower.startBlock, label)
            XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false), label)
            await settle(shower)
            XCTAssertEqual(link.connects, 1, label)
            XCTAssertEqual(http.sent, 1, "\(label): the authorize request went")
        }
    }

    /// Debt allowed on this phone: −0.50 starts.
    func testAllowedDebtLetsMinusFiftyFenStart() async throws {
        link.replies = [FakeFramesApp.idle]
        let shower = try await model(allowsDebt:true)
        shower.noteBalance(Self.owed)
        XCTAssertFalse(shower.balanceBlocks)
        XCTAssertTrue(shower.mayStart)
        XCTAssertNil(shower.startBlock)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        await settle(shower)
        XCTAssertEqual(http.sent, 1)
    }

    /// Allowed while the app runs: the button can be tapped at once.
    func testAllowingDebtLiftsTheBlockAtOnce() async throws {
        let shower = try await model()
        shower.noteBalance(Self.owed)
        XCTAssertFalse(shower.mayStart, "blocked before")
        shower.setAllowsDebt(true)
        XCTAssertTrue(shower.mayStart)
        XCTAssertNil(shower.startBlock)
    }

    /// Taken back: blocked again.
    func testTurningDebtOffBlocksAgain() async throws {
        let shower = try await model(allowsDebt:true)
        shower.noteBalance(Self.owed)
        XCTAssertTrue(shower.mayStart)
        shower.setAllowsDebt(false)
        XCTAssertFalse(shower.mayStart)
        XCTAssertEqual(shower.startBlock, .balanceNegative)
    }

    // MARK: A start under way

    /// Debt turned off while a −0.50 start reads the controller: the permit is revoked before the
    /// authorize request, so neither it nor the open command goes out.
    func testTurningDebtOffDuringAStartRevokesItBeforeTheAuthorize() async throws {
        link.holdExchange = true
        let shower = try await model(allowsDebt:true)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        await waitUntil { self.link.isHolding }
        shower.setAllowsDebt(false)
        link.release(FakeFramesApp.idle)
        await settle(shower)
        XCTAssertEqual(http.sent, 0, "no authorize request")
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand], "only the read-only probe; no open command")
    }

    /// Debt turned off while the explainer waits: nothing runs once the alert is answered.
    func testTurningDebtOffBeforeTheEngineStartsNothing() async throws {
        access.authorization = .notDetermined
        access.hold = true
        let shower = try await model(binding:Fixture.binding, allowsDebt:true)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.page), .explainer)
        shower.confirmExplainer(shower.explainerIntent!.id)
        await waitUntil { self.access.holding }
        shower.setAllowsDebt(false)
        access.release(.allowed)
        await settle(shower)
        XCTAssertEqual(link.connects, 0)
        XCTAssertEqual(http.sent, 0)
    }

    /// Turning debt off over a balance that isn't below zero takes nothing back.
    func testTurningDebtOffOverAGoodBalanceLeavesTheStart() async throws {
        link.holdExchange = true
        let shower = try await model(allowsDebt:true)
        shower.noteBalance(Self.balance(fen:0))
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        await waitUntil { self.link.isHolding }
        shower.setAllowsDebt(false)
        link.release(FakeFramesApp.idle)
        await settle(shower)
        XCTAssertEqual(http.sent, 1)
    }

    /// The balance (unknown or positive at the tap) comes back below zero while the start still
    /// reads the controller: the start's permit is revoked there and then, so neither the
    /// authorize request nor the open command goes out (the read-only probe already went).
    func testABalanceGoingBelowZeroBeforeTheAuthorizeRevokesTheStart() async throws {
        for (label, before) in [("unknown", nil), ("positive", Self.balance(fen:1250))] as [(String, ShowerBalance?)] {
            fresh()
            link.holdExchange = true
            let shower = try await model()
            shower.noteBalance(before)
            XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false), label)
            await waitUntil { self.link.isHolding }
            let permit = shower.startSlot?.permit
            shower.noteBalance(Self.owed)
            XCTAssertEqual(permit?.isOpen, false, "\(label): revoked in the same step")
            link.release(FakeFramesApp.idle)
            await settle(shower)
            XCTAssertEqual(http.sent, 0, "\(label): no authorize request")
            XCTAssertEqual(link.writes, [ShowerFrames.probeCommand], "\(label): no open command")
        }
    }

    /// The authorize request already left (the permit was consumed): a balance below zero
    /// arriving now changes nothing for this start. Its slot and task stay, nothing is sent again.
    func testABalanceGoingBelowZeroAfterTheAuthorizeLeftChangesNothing() async throws {
        let held = HeldHTTP()
        link.replies = [FakeFramesApp.idle]
        let shower = try await model(platform:held)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        let reached = await held.reached()
        XCTAssertTrue(reached, "the authorize request is out")
        let slot = shower.startSlot?.id
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.startSlot?.id, slot, "the start that won is left alone")
        XCTAssertNotNil(shower.startTask)
        held.release()
        await settle(shower)
        XCTAssertEqual(held.sent, 1, "sent once, never again")
    }

    /// The platform, held until `release`, then a successful authorize (synthetic values).
    final class HeldAuthorizeOK: HTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var _sent = 0
        private var waiting: CheckedContinuation<Void, Never>?
        private var released = false
        var sent: Int { lock.withLock { _sent } }
        var isHolding: Bool { lock.withLock { waiting != nil } }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let go: Bool = lock.withLock { _sent += 1; return released }
            if !go { await withCheckedContinuation { c in lock.withLock { waiting = c } } }
            let body = #"{"code":0,"data":{"machineid":"11223344","studentId":"a1b2c3d4","systemData":"000102030405060708090a0b0c0d0e"}}"#
            return HTTPResponse(status:200, headers:["Content-Type":"application/json"], body:Data(body.utf8))
        }
        func release() { lock.withLock { released = true; let w = waiting; waiting = nil; return w }?.resume() }
    }

    /// Consume wins, with an authorize that succeeds: the balance coming back below zero after
    /// the request left interrupts nothing; the open command still goes to the controller.
    func testAfterASuccessfulAuthorizeTheOpenWriteGoesOn() async throws {
        let platform = HeldAuthorizeOK()
        link.replies = [FakeFramesApp.idle, FakeFramesApp.active]
        let shower = try await model(platform:platform)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        await waitUntil { platform.isHolding }
        XCTAssertTrue(platform.isHolding, "the authorize request is out")
        let slot = shower.startSlot?.id
        let permit = shower.startSlot?.permit
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.startSlot?.id, slot, "the start that won is left alone")
        XCTAssertEqual(permit?.revoke(), false, "consumed: nothing to take back")
        platform.release()
        await settle(shower)
        XCTAssertEqual(platform.sent, 1, "one authorize")
        XCTAssertEqual(link.writes.first, ShowerFrames.probeCommand)
        XCTAssertGreaterThanOrEqual(link.writes.count, 2, "the open command was written after the authorize")
        XCTAssertNotEqual(shower.state.phase, .idle, "the start went on")
    }

    /// The same when debt is turned off after the authorize request left.
    func testTurningDebtOffAfterTheAuthorizeLeftChangesNothing() async throws {
        let held = HeldHTTP()
        link.replies = [FakeFramesApp.idle]
        let shower = try await model(allowsDebt:true, platform:held)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.page), .started(firstCheck:false))
        let reached = await held.reached()
        XCTAssertTrue(reached)
        let slot = shower.startSlot?.id
        shower.setAllowsDebt(false)
        XCTAssertEqual(shower.startSlot?.id, slot)
        held.release()
        await settle(shower)
        XCTAssertEqual(held.sent, 1)
    }

    /// The explainer is up when the balance comes back below zero: its 好，开始 asks nothing.
    func testTheExplainersConfirmAfterTheFlipAsksNothing() async throws {
        access.authorization = .notDetermined
        let shower = try await model(binding:Fixture.binding)
        XCTAssertEqual(shower.tapStart(.page), .explainer)
        let id = shower.explainerIntent!.id
        shower.noteBalance(Self.owed)
        shower.confirmExplainer(id)
        await settle(shower)
        XCTAssertEqual(access.requests, 0, "no system alert for a start that can't go")
        XCTAssertNil(shower.startSlot)
        XCTAssertEqual(link.connects, 0)
    }

    /// The same with debt turned off while the explainer is up.
    func testTheExplainersConfirmAfterDebtIsTurnedOffAsksNothing() async throws {
        access.authorization = .notDetermined
        let shower = try await model(binding:Fixture.binding, allowsDebt:true)
        shower.noteBalance(Self.owed)
        XCTAssertEqual(shower.tapStart(.page), .explainer)
        let id = shower.explainerIntent!.id
        shower.setAllowsDebt(false)
        shower.confirmExplainer(id)
        await settle(shower)
        XCTAssertEqual(access.requests, 0)
        XCTAssertEqual(link.connects, 0)
    }

    // MARK: A shower already on

    /// Showering into the red is not interrupted: nothing is sent when the balance comes in,
    /// 结束 and 检查水控状态 stay, and the reason is still the running record's.
    func testARunningShowerIsNotInterrupted() async throws {
        let shower = try await model(record:Fixture.running)
        XCTAssertEqual(shower.state.phase, .running)
        shower.noteBalance(Self.owed)
        await pause(50)
        XCTAssertEqual(shower.state.phase, .running)
        XCTAssertEqual(link.connects, 0, "nothing sent for the balance")
        XCTAssertEqual(http.sent, 0)
        XCTAssertTrue(shower.mayFinish)
        XCTAssertTrue(shower.mayReview)
        XCTAssertEqual(shower.startBlock, .unsettled)
        _ = try? await shower.run(start:false)
        XCTAssertGreaterThanOrEqual(link.connects, 1, "结束 went to the controller")
    }

    // MARK: 清爽's refused face

    /// The tapped look of 清爽's 开始洗澡 on the refused face follows what `tapStart(.retry)`
    /// answered: a refused or not-allowed retry never leaves it spinning.
    func testClearRetrySpinsOnlyForAStartThatWent() {
        XCTAssertFalse(ClearShowerDock.retryKeepsSpinning(after:.notAllowed))
        XCTAssertFalse(ClearShowerDock.retryKeepsSpinning(after:.refused))
        XCTAssertTrue(ClearShowerDock.retryKeepsSpinning(after:.started(firstCheck:false)))
        XCTAssertTrue(ClearShowerDock.retryKeepsSpinning(after:.joined))
    }

    /// The real retry while the balance refuses answers `.notAllowed`, so the face goes back.
    func testTheRealRetryAnswerStopsTheSpinner() async throws {
        link.connectError = .notFound
        let shower = try await model()
        shower.tapStart(.page, showingPage:true)
        await settle(shower)
        XCTAssertTrue(shower.page.mayRetry, "precondition: the face offers 再试一次")
        shower.noteBalance(Self.owed)
        let answer = shower.tapStart(.retry)
        XCTAssertFalse(ClearShowerDock.retryKeepsSpinning(after:answer), "\(answer)")
    }

    /// 开始洗澡 on 清爽's refused face while the balance refuses: off, and never left spinning
    /// 正在处理… after its tap was refused (`retryTapped` stays set until the phase moves).
    func testClearRetryFaceIsOffAndStillWhileBlocked() {
        for (tapped, starting) in [(false, false), (true, false)] {
            let face = ClearShowerDock.retryFace(tapped:tapped, starting:starting, blocked:true)
            XCTAssertFalse(face.spinning, "tapped \(tapped): not spinning")
            XCTAssertFalse(face.enabled, "tapped \(tapped): off")
            XCTAssertEqual(face.title, ClearShowerText.deniedRetry, "tapped \(tapped)")
        }
        let open = ClearShowerDock.retryFace(tapped:false, starting:false, blocked:false)
        XCTAssertTrue(open.enabled, "unchanged without the block")
    }
}
