//
//  SignOutHotWaterTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 退出登录 treats hot water like an account switch. The binding holds the school identity of
/// the person who signs out, and the next sign-in has nobody stored to compare with: without
/// this, the next person's showers would be billed to the person who signed out.
@MainActor
final class SignOutHotWaterTests: XCTestCase {
    private var leaseFiles: [URL] = []

    override func tearDown() {
        leaseFiles.forEach { try? FileManager.default.removeItem(at:$0) }
        leaseFiles = []
        super.tearDown()
    }

    private func models(_ store: ScriptedStore, support: URL? = nil, defaults: UserDefaults = SampleDefaults()) -> (CampusModel, ShowerModel) {
        let leaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("signout-hw-lease-\(UUID().uuidString)")
        leaseFiles.append(leaseURL)
        let services = CampusServices(kind:.live, secureStore:store, defaults:defaults, sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:SampleShowerTransport(), leaseFile:LeaseFile(url:leaseURL),
                                      applicationSupport:support, sharedDidChange:{})
        let reminders = Reminders.sample(defaults:services.defaults)
        let shower = ShowerModel(services:services, reminders:reminders, activities:nil, gate:LiveShowerGate())
        let campus = CampusModel(services:services, stack:services.schoolStack(), reminders:reminders) { shower }
        return (campus, shower)
    }

    func testSignOutRemovesTheBinding() async throws {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        let (campus, shower) = models(store)
        await shower.reloadProfile()
        await waitUntil { shower.gateRecord != .notLoaded }
        XCTAssertNotNil(shower.binding)

        campus.signOut()
        await waitUntil { shower.binding == nil }

        XCTAssertNil(shower.binding)
        XCTAssertNil(try vault.binding())
        XCTAssertFalse(shower.residenceReviewRequired)
    }

    /// A shower that may still be open needs its binding for 结束: the binding stays, and no new
    /// shower starts with it until the dorm is set again.
    func testSignOutDuringAShowerKeepsTheBindingAndBlocksANewStart() async throws {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(Fixture.running)
        let (campus, shower) = models(store)
        await shower.reloadProfile()
        await waitUntil { shower.gateRecord != .notLoaded }

        campus.signOut()

        XCTAssertNotNil(try vault.binding())
        XCTAssertTrue(shower.residenceReviewRequired)
        XCTAssertFalse(shower.mayStart)

        // Once the sign-out and its hot-water step are done, the binding is still there.
        await campus.signOutsFinished()
        XCTAssertEqual(try vault.binding(), Fixture.binding)
        XCTAssertEqual(shower.binding, Fixture.binding)
        XCTAssertTrue(shower.residenceReviewRequired)
        XCTAssertFalse(shower.mayStart)
    }

    /// The first read of the shower record failed, and 退出登录 comes before it is read again: the
    /// default idle is not "no shower". The binding stays (the shower may need it for 结束) and no
    /// new shower starts with it; once the record is read, the running shower is back with it.
    func testSignOutBeforeTheRecordIsReadKeepsTheBinding() async throws {
        let store = ScriptedStore()
        store.sessionReadError = { $0 == 0 ? StorageError(operation:"read", status:-25308) : nil }
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(Fixture.running)
        let (campus, shower) = models(store, support:try Fixture.supportWithProfile())
        XCTAssertNotEqual(shower.gateRecord, .known(.idle), "the first read failed")

        campus.signOut()

        XCTAssertNotNil(try vault.binding())
        XCTAssertTrue(shower.residenceReviewRequired)
        XCTAssertFalse(shower.mayStart)

        await waitUntil { shower.state.phase == .running && shower.mayFinish }
        XCTAssertEqual(shower.state.phase, .running)
        XCTAssertEqual(shower.binding, Fixture.binding)
        XCTAssertEqual(try vault.binding(), Fixture.binding)
        XCTAssertTrue(shower.mayFinish, "结束 still has the binding it needs")
        XCTAssertTrue(shower.residenceReviewRequired)
        XCTAssertFalse(shower.mayStart)
    }

    /// The same at the model: before the record is read, an account switch keeps the binding.
    func testAnAccountSwitchBeforeTheRecordIsReadKeepsTheBinding() async throws {
        let store = ScriptedStore()
        store.sessionReadError = { $0 == 0 ? StorageError(operation:"read", status:-25308) : nil }
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(Fixture.running)
        let (_, shower) = models(store)

        XCTAssertEqual(shower.clearBindingForAccountSwitch(), .keptForReview)
        XCTAssertEqual(try vault.binding(), Fixture.binding)
        XCTAssertTrue(shower.residenceReviewRequired)

        await waitUntil { shower.state.phase == .running }
        XCTAssertEqual(shower.state.phase, .running)
        XCTAssertEqual(shower.binding, Fixture.binding)
    }

    /// 退出登录 that could not delete everything leaves the person signed in: the binding stays
    /// (setting hot water up again isn't needed to try again), but no new shower starts with it.
    func testAFailedSignOutKeepsTheBindingAndBlocksANewStart() async throws {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        let (campus, shower) = models(store, support:try Fixture.supportWithProfile())
        await waitUntil { shower.gateRecord != .notLoaded && shower.profileLoaded }
        XCTAssertTrue(shower.mayStart)
        store.refusing = [.schoolPassword]

        campus.signOut()
        await waitUntil { campus.signOutFailed }

        XCTAssertTrue(campus.signOutFailed)
        XCTAssertEqual(try vault.binding(), Fixture.binding)
        XCTAssertEqual(shower.binding, Fixture.binding)
        XCTAssertTrue(shower.residenceReviewRequired)
        XCTAssertFalse(shower.mayStart)
    }

    /// 退出登录 that went through: the binding goes once it is done.
    func testASignOutThatWentThroughRemovesTheBindingAfterwards() async throws {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        let (campus, shower) = models(store, support:try Fixture.supportWithProfile())
        await waitUntil { shower.gateRecord != .notLoaded && shower.profileLoaded }

        campus.signOut()
        XCTAssertFalse(shower.mayStart, "not with the identity being signed out")
        await waitUntil { shower.binding == nil }

        XCTAssertFalse(campus.signOutFailed)
        XCTAssertNil(shower.binding)
        XCTAssertNil(try vault.binding())
        XCTAssertFalse(shower.residenceReviewRequired)
    }

    private static let heldAlert = "退出没完成，热水暂时开不了。重新核对宿舍水控就能接着用；如果再退一次，退出后要重新设热水。"
    private static let heldLine = "上次退出学校账号没完成，热水暂时开不了。去设置里再退一次，或者重新核对宿舍水控。"
    private static let switchLine = "学校账号退出或换过，先在校日常里重新核对宿舍水控。"

    /// Why 开始洗澡 is refused (what Siri and Shortcuts say).
    private func startRefusal(_ shower: ShowerModel) async -> String? {
        do { _ = try await shower.startFromShortcut(clear:false); return nil }
        catch let failure as ShowerActionFailure { return failure.message }
        catch { return "\(error)" }
    }

    /// A failed 退出登录 that held hot water says so, in the alert and when a start is refused,
    /// also after a relaunch: nothing was switched, the sign-out just has to be done again.
    func testAFailedSignOutThatHeldHotWaterSaysSo() async throws {
        let store = ScriptedStore()
        let defaults = SampleDefaults()
        try StoredShowerVault(store:store).saveBinding(Fixture.binding)
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        let support = try Fixture.supportWithProfile()
        let (campus, shower) = models(store, support:support, defaults:defaults)
        await waitUntil { shower.gateRecord != .notLoaded && shower.profileLoaded }
        store.refusing = [.schoolPassword]

        campus.signOut()
        await waitUntil { campus.signOutFailed }

        XCTAssertTrue(campus.signOutFailed)
        XCTAssertEqual(AccountText.signOutFailed(hotWaterHeld:campus.signOutFailedHeldHotWater), Self.heldAlert)
        let refusal = await startRefusal(shower)
        XCTAssertEqual(refusal, Self.heldLine)

        let (_, relaunched) = models(store, support:support, defaults:defaults)
        await waitUntil { relaunched.gateRecord != .notLoaded && relaunched.profileLoaded }
        let after = await startRefusal(relaunched)
        XCTAssertEqual(after, Self.heldLine, "remembered across a relaunch")
    }

    /// With no hot water set up, a failed 退出登录 holds nothing: the alert stays as it was.
    func testAFailedSignOutWithoutHotWaterKeepsTheShortAlert() async throws {
        let store = ScriptedStore()
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        let (campus, shower) = models(store, support:try Fixture.supportWithProfile())
        await waitUntil { shower.gateRecord != .notLoaded && shower.profileLoaded }
        store.refusing = [.schoolPassword]

        campus.signOut()
        await waitUntil { campus.signOutFailed }

        XCTAssertTrue(campus.signOutFailed)
        XCTAssertFalse(campus.signOutFailedHeldHotWater)
        XCTAssertEqual(AccountText.signOutFailed(hotWaterHeld:campus.signOutFailedHeldHotWater), "退出没完成，再试一次。")
    }

    /// An account switch that keeps the binding for review keeps its own line.
    func testAnAccountSwitchKeepsTheSwitchLine() async throws {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(Fixture.running)
        let (_, shower) = models(store, support:try Fixture.supportWithProfile())
        await waitUntil { shower.state.phase == .running && shower.profileLoaded }

        XCTAssertEqual(shower.clearBindingForAccountSwitch(), .keptForReview)
        XCTAssertEqual(shower.startRefusalText, Self.switchLine)
    }

    /// The dorm checked again after a failed sign-out clears what was remembered: a later
    /// sign-out that holds hot water is not taken for the failed one.
    func testCheckingTheDormAgainForgetsTheFailedSignOut() async throws {
        let store = ScriptedStore()
        let defaults = SampleDefaults()
        try StoredShowerVault(store:store).saveBinding(Fixture.binding)
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        let (campus, shower) = models(store, support:try Fixture.supportWithProfile(), defaults:defaults)
        await waitUntil { shower.gateRecord != .notLoaded && shower.profileLoaded }
        store.refusing = [.schoolPassword]
        campus.signOut()
        await waitUntil { campus.signOutFailed }
        XCTAssertEqual(shower.startRefusalText, Self.heldLine)

        try shower.saveBinding(Fixture.binding)
        XCTAssertFalse(shower.residenceReviewRequired)
        shower.holdForSignOut()
        XCTAssertEqual(shower.startRefusalText, Self.switchLine)
    }

    /// A failed 退出登录, then one that goes through: hot water goes as after any sign-out, and
    /// the failed one is forgotten (a binding set up again isn't refused with its line).
    func testASecondSignOutThatGoesThroughForgetsTheFailedOne() async throws {
        let store = ScriptedStore()
        let defaults = SampleDefaults()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        let (campus, shower) = models(store, support:try Fixture.supportWithProfile(), defaults:defaults)
        await waitUntil { shower.gateRecord != .notLoaded && shower.profileLoaded }
        store.refusing = [.schoolPassword]
        campus.signOut()
        await campus.signOutsFinished()
        XCTAssertTrue(campus.signOutFailed)
        XCTAssertTrue(defaults.bool(forKey:PreferenceKey.showerReviewAfterFailedSignOut))
        XCTAssertEqual(shower.startRefusalText, Self.heldLine)

        store.refusing = []
        campus.signOut()
        await campus.signOutsFinished()

        XCTAssertNil(shower.binding)
        XCTAssertNil(try vault.binding())
        XCTAssertFalse(shower.residenceReviewRequired)
        XCTAssertFalse(defaults.bool(forKey:PreferenceKey.showerReviewAfterFailedSignOut))
        try shower.saveBinding(Fixture.binding)
        shower.holdForSignOut()
        XCTAssertEqual(shower.startRefusalText, Self.switchLine)
    }

    /// A sign-in's clean-up of the previous person, with a 退出登录 coming in while the widget
    /// snapshot is cleared: the binding is whoever's is stored now and stays, and no switch
    /// notice is shown. (The sign-out here fails, so it doesn't remove the binding itself.)
    func testASignOutDuringASignInsCleanUpLeavesTheBinding() async throws {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        let (campus, shower) = models(store, support:try Fixture.supportWithProfile())
        await waitUntil { shower.gateRecord != .notLoaded && shower.profileLoaded }
        store.refusing = [.schoolPassword]
        let started = campus.signOutGeneration
        var hookRan = false
        campus.afterSnapshotCleared = {
            hookRan = true
            campus.signOut()
            await campus.signOutsFinished()
        }

        await campus.previousPersonCleared(unconfirmed:false, dormAndMeterCleared:false, since:started)

        XCTAssertTrue(hookRan)
        XCTAssertTrue(campus.signOutFailed)
        XCTAssertEqual(try vault.binding(), Fixture.binding)
        XCTAssertEqual(shower.binding, Fixture.binding)
        XCTAssertNil(campus.switchNotice)
    }
}
