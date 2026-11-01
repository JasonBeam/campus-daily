import XCTest
@testable import Core

/// The reset marker: starts refused while a reset runs, never for good, and a reset the app was
/// killed in finished (or stopped by the same locks) at the next launch.
final class ResetMarkerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testStartsAreRefusedOnlyWhileTheMarkerIsFresh() throws {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        XCTAssertFalse(marker.refusesStarts(at: t0), "no marker")
        XCTAssertNoThrow(try marker.checkStart(at: t0))
        try marker.begin(at: t0)
        XCTAssertTrue(marker.refusesStarts(at: t0))
        XCTAssertTrue(marker.refusesStarts(at: t0.addingTimeInterval(ResetMarker.staleAfter - 1)))
        XCTAssertThrowsError(try marker.checkStart(at: t0)) { XCTAssertEqual($0 as? AppReset.InProgress, AppReset.InProgress()) }
        XCTAssertFalse(marker.refusesStarts(at: t0.addingTimeInterval(ResetMarker.staleAfter)), "stale: never blocks for good")
        XCTAssertFalse(marker.refusesStarts(at: t0.addingTimeInterval(-ResetMarker.staleAfter - 1)), "clock set back far")
        try marker.end()
        XCTAssertFalse(marker.refusesStarts(at: t0))
    }

    func testAnUnreadableMarkerRefusesNothingAndResumesNothing() async throws {
        let store = InMemorySecureStore()
        try ResetMarker(store: store).begin(at: t0)
        store.failReads()
        XCTAssertFalse(ResetMarker(store: store).refusesStarts(at: t0))
        XCTAssertNil(ResetMarker(store: store).startedAt())
    }

    /// What the in-app button and the shortcut both show.
    func testTheRefusalSaysResetting() {
        XCTAssertEqual(AppReset.InProgress().localizedDescription, "正在重置")
    }

    func testStoredRecordsLock() throws {
        let store = InMemorySecureStore()
        XCTAssertNil(AppReset.storedLock(store: store))
        try StoredShowerVault(store: store).saveShowerState(ShowerState(phase: .running))
        XCTAssertNotNil(AppReset.storedLock(store: store))
        try StoredShowerVault(store: store).saveShowerState(nil)
        try store.write(Data("not json".utf8), for: .laundryCheckout)
        XCTAssertEqual(AppReset.storedLock(store: store), .recordsUnreadable)
    }

    @MainActor func resume(_ store: InMemorySecureStore, at now: Date, steps: inout [String]) async throws -> AppReset.Resumed? {
        let suite = "reset-resume-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var log: [String] = []
        let result = try await AppReset.resume(
            marker: ResetMarker(store: store), now: now,
            lock: { AppReset.storedLock(store: store) },
            signOut: { log.append("signOut") },
            clear: { log.append("clear"); try AppReset.clear(store: store, preferences: defaults, preferencesDomain: suite, files: []) },
            reload: { log.append("reload") })
        steps = log
        return result
    }

    /// Killed after the marker (part of the clear done or not): the next launch finishes it.
    @MainActor func testAnInterruptedResetCompletesOnRelaunch() async throws {
        let store = InMemorySecureStore()
        try ResetMarker(store: store).begin(at: t0)
        try StoredSchoolVault(store: store).saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try store.write(Data("x".utf8), for: .sharedSnapshot)
        var steps: [String] = []
        let resumed = try await resume(store, at: t0.addingTimeInterval(30), steps: &steps)
        XCTAssertEqual(resumed, .completed)
        XCTAssertEqual(steps, ["signOut", "clear", "reload"])
        for key in StoreKey.allCases { XCTAssertNil(try store.read(key), key.rawValue) }
    }

    /// A marker older than a few minutes (a reset killed days ago): deleted, and nothing the user
    /// set up since is signed out or cleared. The caller is told the reset was left unfinished.
    @MainActor func testAStaleMarkerIsDroppedWithoutClearing() async throws {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        try marker.begin(at: t0)
        try StoredSchoolVault(store: store).saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try store.write(Data("x".utf8), for: .sharedSnapshot)
        for later in [t0.addingTimeInterval(ResetMarker.staleAfter), t0.addingTimeInterval(-ResetMarker.staleAfter - 1),
                      t0.addingTimeInterval(3 * 86_400)] {
            try marker.begin(at: t0)
            var steps: [String] = []
            let resumed = try await resume(store, at: later, steps: &steps)
            XCTAssertEqual(resumed, .abandoned)
            XCTAssertEqual(steps, [], "nothing signed out, cleared or reloaded")
            XCTAssertNil(marker.startedAt())
            XCTAssertNotNil(try StoredSchoolVault(store: store).account())
            XCTAssertNotNil(try store.read(.sharedSnapshot))
        }
    }

    /// A fresh marker, and a record that locks reset (a shower still to be settled): the record is
    /// left alone, the marker goes, and the caller is told why (「没有重置」).
    @MainActor func testAFreshMarkerStoppedByALockClearsNothing() async throws {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        try marker.begin(at: t0)
        let running = ShowerState(phase: .running, machineID: "11223344")
        try StoredShowerVault(store: store).saveShowerState(running)
        try StoredShowerVault(store: store).saveBinding(ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991"))
        var steps: [String] = []
        let resumed = try await resume(store, at: t0.addingTimeInterval(30), steps: &steps)
        guard case .stopped(let stop)? = resumed else { return XCTFail("\(String(describing: resumed))") }
        XCTAssertEqual(stop.lock, AppReset.storedLock(store: store))
        XCTAssertFalse(stop.signedOut)
        XCTAssertEqual(steps, [], "nothing signed out, cleared or reloaded")
        XCTAssertEqual(try StoredShowerVault(store: store).showerState(), running)
        XCTAssertNotNil(try StoredShowerVault(store: store).binding())
        XCTAssertNil(marker.startedAt())
    }

    /// Resumed at launch, and a shower starts while the sign-out runs: stopped on the second
    /// check, and the caller learns the sign-out already happened (so it doesn't say nothing
    /// was cleared). The shower record stays.
    @MainActor func testALockFoundAfterTheSignOutSaysSo() async throws {
        let store = InMemorySecureStore()
        try ResetMarker(store: store).begin(at: t0)
        let running = ShowerState(phase: .running, machineID: "11223344")
        var steps: [String] = []
        let resumed = try await AppReset.resume(
            marker: ResetMarker(store: store), now: t0.addingTimeInterval(30),
            lock: { AppReset.storedLock(store: store) },
            signOut: {
                steps.append("signOut")
                try? StoredShowerVault(store: store).saveShowerState(running)
            },
            clear: { steps.append("clear") }, reload: { steps.append("reload") }, resync: { steps.append("resync") })
        XCTAssertEqual(resumed, .stopped(AppReset.Stop(.showering, signedOut: true)))
        XCTAssertEqual(steps, ["signOut", "resync"])
        XCTAssertEqual(try StoredShowerVault(store: store).showerState(), running)
        XCTAssertNil(ResetMarker(store: store).startedAt())
    }

    /// Told once: the marker is gone, so the next launch has nothing to say.
    @MainActor func testAnAbandonedResetIsToldOnce() async throws {
        let store = InMemorySecureStore()
        try ResetMarker(store: store).begin(at: t0)
        var steps: [String] = []
        let later = t0.addingTimeInterval(ResetMarker.staleAfter + 60)
        let first = try await resume(store, at: later, steps: &steps)
        let second = try await resume(store, at: later.addingTimeInterval(60), steps: &steps)
        XCTAssertEqual(first, .abandoned)
        XCTAssertNil(second)
    }

    @MainActor func testNoMarkerNothingToResume() async throws {
        let store = InMemorySecureStore()
        try store.write(Data("x".utf8), for: .sharedSnapshot)
        var steps: [String] = []
        let resumed = try await resume(store, at: t0, steps: &steps)
        XCTAssertNil(resumed)
        XCTAssertEqual(steps, [])
        XCTAssertNotNil(try store.read(.sharedSnapshot))
    }
}
