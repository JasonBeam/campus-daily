import XCTest
@testable import Core
import CoreTestSupport

final class AppResetTests: XCTestCase {
    /// Every stored item, the saved school password included, is gone after a reset; files the
    /// app wrote are deleted and other files are left alone.
    func testResetClearsEverySeededItem() throws {
        let store = InMemorySecureStore()
        let school = StoredSchoolVault(store: store)
        try school.savePortalToken(PortalToken("PORTAL", expiresAt: Date(timeIntervalSince1970: 1_800_000_000)))
        try school.saveEcyktSession(EcyktSession(token: "t", syscustid: "s"))
        try school.saveProfile(SchoolProfile(residence: PortalResidence(raw: "示例校区99栋9号1层991房")))
        try school.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try school.saveLoginDeviceID("99000000000000000000000000000991")
        for key in StoreKey.allCases where try store.read(key) == nil { try store.write(Data(key.rawValue.utf8), for: key) }
        for key in StoreKey.allCases { XCTAssertNotNil(try store.read(key), "seeded \(key.rawValue)") }

        let suite = "reset-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PreferenceKey.schoolLaundry)
        defaults.set(20, forKey: PreferenceKey.reminder("cardLine"))
        defaults.set("x", forKey: PreferenceKey.prefix + "laundry.machines")
        defaults.set(true, forKey: "didSeeQuickSetup")
        let otherSuite = suite + "-other"
        let otherDefaults = try XCTUnwrap(UserDefaults(suiteName: otherSuite))
        defer { otherDefaults.removePersistentDomain(forName: otherSuite) }
        otherDefaults.set("kept", forKey: "unrelated")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let water = folder.appendingPathComponent("Water", isDirectory: true)
        try FileManager.default.createDirectory(at: water, withIntermediateDirectories: true)
        try Data("imported".utf8).write(to: water.appendingPathComponent("imported.waterconfig"))
        let other = folder.appendingPathComponent("bundled-like.waterconfig")
        try Data("bundled".utf8).write(to: other)
        defer { try? FileManager.default.removeItem(at: folder) }

        try AppReset.clear(store: store, preferences: defaults, preferencesDomain: suite, files: [water, folder.appendingPathComponent("missing")])

        for key in StoreKey.allCases { XCTAssertNil(try store.read(key), key.rawValue) }
        XCTAssertNil(try school.account(), "the saved password is gone")
        XCTAssertNil(defaults.object(forKey: PreferenceKey.schoolLaundry))
        XCTAssertNil(defaults.object(forKey: PreferenceKey.reminder("cardLine")))
        XCTAssertNil(defaults.object(forKey: PreferenceKey.prefix + "laundry.machines"))
        XCTAssertNil(defaults.object(forKey: "didSeeQuickSetup"), "a preference without the xrc. prefix goes too")
        XCTAssertEqual(otherDefaults.string(forKey: "unrelated"), "kept")
        XCTAssertFalse(FileManager.default.fileExists(atPath: water.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    /// A new Keychain item is cleared by reset too; this count makes adding one a conscious step.
    func testResetCoversEveryKeychainItem() {
        XCTAssertEqual(Set(AppReset.keychainItems), Set(StoreKey.allCases))
        XCTAssertEqual(AppReset.keychainItems.count, 14, "a new item: check reset clears it, then update this count")
        XCTAssertEqual(AppReset.keychainItems.last, .sharedResetMarker, "the marker goes last")
        // The refresh lease is an item of its own; the credential times live inside the
        // card session and portal token items, so they go with them.
        XCTAssertTrue(AppReset.keychainItems.contains(.sharedRefreshLease))
        XCTAssertTrue(AppReset.keychainItems.contains(.sharedCredentialLog))
        XCTAssertTrue(AppReset.keychainItems.contains(.schoolEcykt))
        XCTAssertTrue(AppReset.keychainItems.contains(.schoolPortal))
    }

    /// A live lease and stamped credentials is gone after a reset, and after
    /// a sign-out (school session first, then the refresher).
    func testResetAndSignOutLeaveNoLeaseOrCredentialTimes() async throws {
        func seed(_ store: InMemorySecureStore) throws {
            let school = StoredSchoolVault(store: store)
            var session = EcyktSession(token: "t", syscustid: "s", obtainedAt: Date(timeIntervalSince1970: 1_800_000_000))
            session.lastAliveAt = Date(timeIntervalSince1970: 1_800_003_600)
            try school.saveEcyktSession(session)
            try school.savePortalToken(PortalToken("PORTAL", obtainedAt: Date(timeIntervalSince1970: 1_800_000_000)))
            XCTAssertTrue(RefreshLease(file: store.leaseFile, owner: "widget-1").acquire())
            try SharedSnapshotStore(store: store).saveSnapshot(HomeSnapshot(needsLogin: true, checkedAt: Date()))
        }
        let resetStore = InMemorySecureStore()
        try seed(resetStore)
        let suite = "reset-s3-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try AppReset.clear(store: resetStore, preferences: defaults, preferencesDomain: suite, files: [])
        for key in StoreKey.allCases { XCTAssertNil(try resetStore.read(key), key.rawValue) }

        let signOutStore = InMemorySecureStore()
        try seed(signOutStore)
        let http = URLSessionHTTPClient(allowedHosts: [])
        let stack = SchoolRefreshStack(store: signOutStore, http: http, role: "app", leaseWait: 0, leaseFile: signOutStore.leaseFile, diagnostic: { _ in })
        try await stack.session.signOut()
        try await stack.refresher.clear()
        XCTAssertNil(try signOutStore.read(.schoolEcykt), "card session and its times")
        XCTAssertNil(try signOutStore.read(.schoolPortal), "portal token and its time")
        XCTAssertNil(signOutStore.leaseFile.storedOwner(), "the other process's lease too")
        XCTAssertEqual(try SharedSnapshotStore(store: signOutStore).loadSnapshot(), .empty)
    }

    func testFailedDeleteIsReportedAndTheRestStillCleared() throws {
        let store = InMemorySecureStore()
        for key in StoreKey.allCases { try store.write(Data("x".utf8), for: key) }
        store.failWrites(to: .schoolPassword)
        let suite = "reset-fail-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertThrowsError(try AppReset.clear(store: store, preferences: defaults, preferencesDomain: suite, files: [])) {
            XCTAssertEqual(($0 as? AppReset.Failure)?.items, ["school.password"])
        }
        for key in StoreKey.allCases where key != .schoolPassword && key != .sharedResetMarker {
            XCTAssertNil(try store.read(key), key.rawValue)
        }
        XCTAssertNotNil(try store.read(.sharedResetMarker), "deleted only after everything else (run removes it after a failure)")
    }

    /// An unfinished laundry order locks reset too; the shower reasons come first.
    func testResetWaitsForAnUnfinishedLaundryOrder() {
        XCTAssertNil(AppReset.lock(shower: .idle, laundry: LaundryPhase.none))
        XCTAssertNil(AppReset.lock(shower: nil, laundry: nil))
        for phase in LaundryPhase.allCases where phase != .none {
            XCTAssertEqual(AppReset.lock(shower: .idle, laundry: phase), .laundry, "\(phase)")
        }
        XCTAssertEqual(AppReset.lock(shower: nil, laundry: LaundryPhase.none, laundryBusy: true), .laundry)
        XCTAssertEqual(AppReset.lock(shower: ShowerState(phase: .running), laundry: .active), .showering)
    }

    func testResetWaitsForTheShowerAndItsSettlement() {
        XCTAssertNil(AppReset.lock(shower: nil))
        XCTAssertNil(AppReset.lock(shower: .idle))
        XCTAssertNil(AppReset.lock(shower: ShowerState(phase: .done)))
        XCTAssertNil(AppReset.lock(shower: ShowerState(phase: .failed, failure: ShowerFailure(reason: .deviceUnavailable, needsReview: false))))
        for phase in [ShowerPhase.authorizing, .writePending, .running, .closing, .settling] {
            XCTAssertEqual(AppReset.lock(shower: ShowerState(phase: phase)), .showering, "\(phase)")
        }
        XCTAssertEqual(AppReset.lock(shower: ShowerState(phase: .failed, failure: ShowerFailure(reason: .settleUncertain, needsReview: true))),
                       .unsettled)
        XCTAssertEqual(AppReset.lock(shower: ShowerState(phase: .running, stateReviewRequired: true)), .unsettled)
    }

    func testUnreadableRecordsAndAControllerCheckLockReset() {
        XCTAssertEqual(AppReset.lock(shower: .idle, recordsUnreadable: true), .recordsUnreadable)
        XCTAssertEqual(AppReset.lock(shower: ShowerState(phase: .running), recordsUnreadable: true), .recordsUnreadable)
        XCTAssertEqual(AppReset.lock(shower: .idle, checkingController: true), .checkingController)
        XCTAssertEqual(AppReset.lock(shower: ShowerState(phase: .running), checkingController: true), .showering)
        XCTAssertNil(AppReset.lock(shower: .idle, recordsUnreadable: false, checkingController: false))
    }

    /// marker → lock → sign out → marker again → lock → clear → reload; the marker goes with a
    /// successful clear.
    @MainActor func testResetRunsItsStepsInOrder() async throws {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        var steps: [String] = []
        let stopped = try await AppReset.run(marker: marker, now: Date(),
                                             lock: { steps.append(marker.startedAt() == nil ? "lock without marker" : "lock"); return nil },
                                             signOut: { steps.append("signOut") },
                                             clear: { steps.append("clear"); try marker.end() },
                                             reload: { steps.append("reload") })
        XCTAssertNil(stopped)
        XCTAssertEqual(steps, ["lock", "signOut", "lock", "clear", "reload"], "each lock check after the marker")
        XCTAssertNil(marker.startedAt())
    }

    /// A lock: nothing signed out, cleared or reloaded, and the marker is gone again.
    @MainActor func testALockTouchesNothingAndRemovesTheMarker() async throws {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        var steps: [String] = []
        let stopped = try await AppReset.run(marker: marker, now: Date(), lock: { .laundry }, signOut: { steps.append("signOut") },
                                             clear: { steps.append("clear") }, reload: { steps.append("reload") })
        XCTAssertEqual(stopped, AppReset.Stop(.laundry, signedOut: false))
        XCTAssertEqual(steps, [])
        XCTAssertNil(marker.startedAt())
        XCTAssertNil(try store.read(.sharedResetMarker))
    }

    /// The sign-out took longer than the marker lasts and a shower started meanwhile: the marker
    /// is written again before the clear, the second check finds the shower, nothing is cleared.
    @MainActor func testAShowerStartedDuringALongSignOutStopsTheClear() async throws {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        let t0 = Date(timeIntervalSince1970: 1_793_300_000)
        var now = t0
        var showering = false
        var steps: [String] = []
        let stopped = try await AppReset.run(marker: marker, now: t0, clock: { now },
                                             lock: { showering ? .showering : nil },
                                             signOut: {
                                                 steps.append("signOut")
                                                 now = t0.addingTimeInterval(ResetMarker.staleAfter + 60)
                                                 XCTAssertFalse(marker.refusesStarts(at: now), "stale by now")
                                                 showering = true
                                             },
                                             clear: { steps.append("clear") }, reload: { steps.append("reload") },
                                             resync: { steps.append("resync") })
        XCTAssertEqual(stopped, AppReset.Stop(.showering, signedOut: true), "told the sign-out happened")
        XCTAssertEqual(steps, ["signOut", "resync"], "the running shower's Live Activity and reminder are not ended")
        XCTAssertNil(marker.startedAt())
    }

    /// The marker is fresh again for the clear, however long the sign-out took.
    @MainActor func testTheMarkerIsFreshAgainForTheClear() async throws {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        let t0 = Date(timeIntervalSince1970: 1_793_300_000)
        var now = t0
        var refusedDuringClear = false
        _ = try await AppReset.run(marker: marker, now: t0, clock: { now }, lock: { nil },
                                   signOut: { now = t0.addingTimeInterval(ResetMarker.staleAfter + 60) },
                                   clear: { refusedDuringClear = marker.refusesStarts(at: now); try marker.end() }, reload: {})
        XCTAssertTrue(refusedDuringClear)
    }

    /// The marker can't be written again after the sign-out: stopped, and the running models
    /// are put back in step (resync), not reloaded as after a clear.
    @MainActor func testAMarkerLostAfterTheSignOutResyncsWithoutReload() async {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        var steps: [String] = []
        do {
            _ = try await AppReset.run(marker: marker, now: Date(), lock: { nil },
                                       signOut: { steps.append("signOut"); store.failWrites(to: .sharedResetMarker) },
                                       clear: { steps.append("clear") }, reload: { steps.append("reload") },
                                       resync: { steps.append("resync") })
            XCTFail("expected the storage error")
        } catch { XCTAssertTrue(error is StorageError) }
        XCTAssertEqual(steps, ["signOut", "resync"])
    }

    /// After a reset stopped behind the sign-out, the lock screen and 「还没结束洗澡？」 follow
    /// the record as on any change: water that may run keeps 结束并结算 and the reminder, an end
    /// still settling stays as settling, a failed one shows 「不确定」 for 15 minutes, nothing
    /// left ends it; laundry is never touched.
    func testTheResyncKeepsARunningShowersLockScreenAndReminder() {
        let start = Date(timeIntervalSince1970: 1_793_000_000), now = start.addingTimeInterval(600)
        let running = AppReset.Resync(shower: ShowerState(phase: .running, startedAt: start), now: now)
        XCTAssertEqual(running.showerReminderStart, start)
        XCTAssertEqual(running.showerActivity, .show(startedAt: start, writeUnconfirmed: false))
        let pending = AppReset.Resync(shower: ShowerState(phase: .writePending, startedAt: start), now: now)
        XCTAssertEqual(pending.showerReminderStart, start, "water may run while the write is unconfirmed")
        XCTAssertEqual(pending.showerActivity, .show(startedAt: start, writeUnconfirmed: true))
        let settling = AppReset.Resync(shower: ShowerState(phase: .settling, startedAt: start), now: now)
        XCTAssertNil(settling.showerReminderStart)
        XCTAssertEqual(settling.showerActivity, .settling(startedAt: start), "the end is still on the lock screen")
        let failed = AppReset.Resync(shower: ShowerState(phase: .failed, startedAt: start,
                                                         failure: ShowerFailure(reason: .settleUncertain, needsReview: true)), now: now)
        XCTAssertNil(failed.showerReminderStart)
        XCTAssertEqual(failed.showerActivity, .unconfirmed(startedAt: start, dismissAfter: 15 * 60))
        XCTAssertTrue(failed.showerActivity.keepsActivity)
        let idle = AppReset.Resync(shower: .idle, now: now)
        XCTAssertNil(idle.showerReminderStart)
        XCTAssertEqual(idle.showerActivity, .end)
        XCTAssertFalse(idle.showerActivity.keepsActivity)
        XCTAssertTrue(idle.leavesLaundry && running.leavesLaundry)
    }

    /// A settled shower shows its minutes and the receipt's amount only, then goes.
    func testASettledShowerShowsTheReceiptThenGoes() {
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        let done = ShowerState(phase: .done, startedAt: start, endedAt: start.addingTimeInterval(8 * 60 + 40))
        XCTAssertEqual(ShowerActivityAction(done, now: start.addingTimeInterval(3600)),
                       .settled(startedAt: start, minutes: 9, amountYuan: nil, dismissAfter: 4))
        XCTAssertEqual(ShowerActivityAction(ShowerState(phase: .authorizing, startedAt: start), now: start), .leave)
    }

    /// A marker that can't be written: the reset does not start at all.
    @MainActor func testNoMarkerNoReset() async {
        let store = InMemorySecureStore()
        store.failWrites(to: .sharedResetMarker)
        var steps: [String] = []
        do {
            _ = try await AppReset.run(marker: ResetMarker(store: store), now: Date(), lock: { steps.append("lock"); return nil },
                                       signOut: { steps.append("signOut") }, clear: { steps.append("clear") },
                                       reload: { steps.append("reload") })
            XCTFail("expected the storage error")
        } catch { XCTAssertTrue(error is StorageError) }
        XCTAssertEqual(steps, [])
    }

    /// A failed clear still reloads and reports, and the marker goes: nothing clears later.
    @MainActor func testAFailedClearStillReloadsAndReports() async {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        var reloaded = false
        do {
            _ = try await AppReset.run(marker: marker, now: Date(), lock: { nil }, signOut: {},
                                       clear: { throw AppReset.Failure(items: ["x"]) }, reload: { reloaded = true })
            XCTFail("expected the failure")
        } catch { XCTAssertEqual(error as? AppReset.Failure, AppReset.Failure(items: ["x"])) }
        XCTAssertTrue(reloaded)
        XCTAssertNil(marker.startedAt())
        XCTAssertNil(try? store.read(.sharedResetMarker))
    }

    /// A Keychain item that can't be deleted: the user is told, the marker goes, and a relaunch
    /// (now or days later, after signing in again) clears nothing.
    @MainActor func testAFailedResetLeavesNothingToFireLater() async throws {
        let store = InMemorySecureStore()
        let marker = ResetMarker(store: store)
        let suite = "reset-failed-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clear = { try AppReset.clear(store: store, preferences: defaults, preferencesDomain: suite, files: []) }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.failWrites(to: .schoolPassword)
        do {
            _ = try await AppReset.run(marker: marker, now: t0, lock: { nil }, signOut: {}, clear: clear, reload: {})
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "重置没做完，有些东西没清掉。再试一次。")
        }
        XCTAssertNil(marker.startedAt())

        store.failWrites(to: .schoolPassword, false)
        try StoredSchoolVault(store: store).saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        for later in [t0.addingTimeInterval(30), t0.addingTimeInterval(3 * 86_400)] {
            var steps: [String] = []
            let resumed = try await AppReset.resume(marker: marker, now: later, lock: { nil },
                                                    signOut: { steps.append("signOut") },
                                                    clear: { steps.append("clear"); try clear() },
                                                    reload: { steps.append("reload") })
            XCTAssertNil(resumed)
            XCTAssertEqual(steps, [])
            XCTAssertNotNil(try StoredSchoolVault(store: store).account())
        }
    }
}
