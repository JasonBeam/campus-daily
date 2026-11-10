import XCTest
import Core
import CoreTestSupport

/// While 「先看看示例」 is shown the live app keeps working as usual: what it writes lands in the
/// live Keychain and preferences at once (nothing is held for later), and the sample, on its
/// own services, sees none of it.
@MainActor
final class LiveWorkDuringSampleTests: XCTestCase {
    func testLiveWritesDuringTheSampleLandAtOnce() throws {
        let keychain = InMemorySecureStore()
        let suite = "xrc.live-probe.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        // As the app builds its live stores: the Keychain and preferences themselves.
        let store: SecureStore = keychain
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let sample = SampleMode.overIdleShower()
        sample.enter()

        try store.write(Data("live".utf8), for: .schoolPassword)
        defaults.set(true, forKey: "xrc.live-probe")

        XCTAssertEqual(try keychain.read(.schoolPassword), Data("live".utf8), "the live Keychain write was held")
        XCTAssertEqual(UserDefaults(suiteName: suite)?.object(forKey: "xrc.live-probe") as? Bool, true,
                       "the live preference write was held")
        let services = try XCTUnwrap(sample.services)
        XCTAssertNil(try services.secureStore.read(.schoolPassword))
        XCTAssertNil(services.defaults.object(forKey: "xrc.live-probe"))
        sample.leave()
    }
}
