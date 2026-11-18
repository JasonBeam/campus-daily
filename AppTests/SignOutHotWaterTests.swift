import XCTest
import Core
@testable import XiaoRiChang

/// 退出登录 treats hot water like an account switch. The binding holds the school identity of
/// the person who signs out, and the next sign-in has nobody stored to compare with: without
/// this, the next person's showers would be billed to the person who signed out.
@MainActor
final class SignOutHotWaterTests: XCTestCase {
    private func models(_ store: ScriptedStore) -> (CampusModel, ShowerModel) {
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:SampleShowerTransport(), leaseFile:nil,
                                      applicationSupport:nil, sharedDidChange:{})
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
}
