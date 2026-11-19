import XCTest
import Core
@testable import XiaoRiChang

/// The live `ShowerModel` exposes the kept showers (`ShowerRetainedSummary`) read from its vault:
/// nothing when none are kept or the list can't be read.
@MainActor
final class ShowerModelRetainedTests: XCTestCase {
    /// A shower kept under `Fixture.binding`, as a next use keeps it.
    private func storeWithAKeptShower() throws -> ScriptedStore {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.retainShower(Fixture.awaitingReview)
        return store
    }

    func testTheModelReadsTheKeptShowers() throws {
        let (model, _) = liveShowerModel(store:try storeWithAKeptShower())
        XCTAssertEqual(model.retained?.count, 1)
        XCTAssertEqual(model.retained?.entries.first?.reason, .settleUnconfirmed)
    }

    /// The person signed out or changed: their kept showers are no longer shown, with the
    /// binding gone and also while it waits for the dorm to be set again. They stay stored.
    func testKeptShowersAreHiddenAfterAnAccountSwitch() async throws {
        let store = try storeWithAKeptShower()
        let (model, _) = liveShowerModel(store:store)
        XCTAssertEqual(model.clearBindingForAccountSwitch(), .cleared)
        XCTAssertNil(model.retained)

        let busy = try storeWithAKeptShower()
        try StoredShowerVault(store:busy).saveShowerState(Fixture.running)
        let (waiting, _) = liveShowerModel(store:busy)
        XCTAssertEqual(waiting.retained?.count, 1)
        XCTAssertEqual(waiting.clearBindingForAccountSwitch(), .keptForReview)
        XCTAssertNil(waiting.retained)
        XCTAssertEqual(try StoredShowerVault(store:busy).retainedShowers().count, 1)
    }

    /// 开始洗澡 from Siri or Shortcuts over a shower that is over keeps that record as the page's
    /// 开始下一次洗澡 does, and the model shows it at once.
    func testAShowerKeptByTheShortcutIsShownAtOnce() async throws {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(Fixture.awaitingReview)
        let link = ScriptedControllerLink()
        // The controller is idle and names the bound machine.
        link.replies = [Data([0x55, 0x11, 0x22, 0x33, 0x44] + [UInt8](repeating:0, count:15))]
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:link, leaseFile:nil,
                                      applicationSupport:try Fixture.supportWithProfile(), sharedDidChange:{})
        let model = ShowerModel(services:services, reminders:.sample(defaults:services.defaults), activities:nil, gate:LiveShowerGate())
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded }
        XCTAssertNil(model.retained)

        _ = try? await model.startFromShortcut(clear:false)

        XCTAssertEqual(try vault.retainedShowersForBinding().count, 1, "the step kept the record")
        XCTAssertEqual(model.retained?.count, 1)
    }

    func testNoneKeptOrUnreadableIsNil() throws {
        XCTAssertNil(liveShowerModel(store:ScriptedStore()).0.retained)
        let store = ScriptedStore()
        try store.write(Data("not json".utf8), for:.showerRetained)
        XCTAssertNil(liveShowerModel(store:store).0.retained)
    }
}
