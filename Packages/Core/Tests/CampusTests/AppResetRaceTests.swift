import XCTest
@testable import Core
import CoreTestSupport

final class AppResetRaceTests: XCTestCase {
    /// A school refresh in flight when reset starts finishes after the clear and writes nothing back.
    @MainActor func testARefreshInFlightWritesNothingBackAfterReset() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let hold = SchoolSignOutRaceTests.Hold(h, self, suffix: "/getUserBalance")
        let session = h.session()
        let refresher = SnapshotRefresher(school: session, store: h.snapshots)
        let reading = Task { await refresher.refresh(inBackground: false) }
        await fulfillment(of: [hold.reached], timeout: 5)
        let suite = "reset-race-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stopped = try await AppReset.run(
            marker: ResetMarker(store: h.store), now: Date(),
            lock: { nil },
            signOut: { try? await session.signOut(); try? await refresher.clear() },
            clear: { try AppReset.clear(store: h.store, preferences: defaults, preferencesDomain: suite, files: []) },
            reload: {})
        XCTAssertNil(stopped)
        hold.release.signal()
        _ = await reading.value
        for key in StoreKey.allCases { XCTAssertNil(try h.store.read(key), "\(key.rawValue) written back") }
    }
}
