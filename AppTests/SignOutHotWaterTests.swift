import XCTest
import Core
@testable import XiaoRiChang

/// 退出登录 treats hot water like an account switch. The binding holds the school identity of
/// the person who signs out, and the next sign-in has nobody stored to compare with: without
/// this, the next person's showers would be billed to the person who signed out.
@MainActor
final class SignOutHotWaterTests: XCTestCase {
    private func models(_ store: ScriptedStore, support: URL? = nil) -> (CampusModel, ShowerModel) {
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:SampleShowerTransport(), leaseFile:nil,
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
}
