//
//  SessionEpochTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/26.
//

import XCTest
@testable import Core
import CoreTestSupport

/// Synthetic interruption, cross-process concurrency, upgrade migration, fail-closed lock,
/// and widget pre-completion re-check tests for `SessionEpoch`.
final class SessionEpochTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_793_003_600)
    private let balanceA = Money(fen: 4321)
    private let balanceB = Money(fen: 8765)

    private func snapshot(balance: Money, at date: Date, epochID: String?) -> HomeSnapshot {
        var s = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: date))
        s = SchoolSnapshotReducer.reduce(s, .balance(.success(balance), at: date))
        s.epochID = epochID
        return s
    }

    private func seedAccountA(in store: SecureStore, epoch: SessionEpoch? = nil, withSnapshot: Bool = true) throws {
        let vault = StoredSchoolVault(store: store)
        var session = T.session()
        session.cardUnionID = SchoolAccountSwitchTests.otherCard
        try vault.saveEcyktSession(session)
        try vault.savePortalToken(PortalToken("PORTAL-A"))
        try vault.saveProfile(SchoolProfile(residence: PortalResidence(raw: "星湖校区98栋8号1层881房"), meter: Harness.roomBinding))
        try vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try vault.saveLoginDeviceID("99000000000000000000000000000991")
        if let epoch {
            try vault.saveSessionEpoch(epoch)
        }
        if withSnapshot {
            try SharedSnapshotStore(store: store).saveSnapshot(snapshot(balance: balanceA, at: t0, epochID: epoch?.id))
        }
    }

    // MARK: 1. Encoding & Privacy

    func testSessionEpochEncodesOnlyIDAndPhase() throws {
        let epoch = SessionEpoch(id: "epoch-test-1", phase: .active)
        let data = try JSONEncoder().encode(epoch)
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(raw.keys), ["id", "phase"], "no timestamp or PII fields allowed")
        XCTAssertEqual(raw["id"] as? String, "epoch-test-1")
        XCTAssertEqual(raw["phase"] as? String, "active")
    }

    func testUndecodableEpochFailsClosedForSnapshotAndWidget() throws {
        let store = InMemorySecureStore()
        try seedAccountA(in: store, epoch: nil)
        try store.write(Data("not-json".utf8), for: .sharedSessionEpoch)

        let snapshots = SharedSnapshotStore(store: store)
        let vault = StoredSchoolVault(store: store)
        XCTAssertThrowsError(try snapshots.loadSnapshot()) { error in
            XCTAssertTrue((error as? StorageError)?.isUndecodable == true)
        }
        XCTAssertNil(WidgetStoredData.read(snapshots: snapshots, vault: vault))
        XCTAssertEqual(WidgetDrawChoice.choose(WidgetStoredData.read(snapshots: snapshots, vault: vault)),
                       .noNumbers(retryAfter: WidgetStoredData.unreadableRetry))
    }

    // MARK: 2. Synthetic Interruption & Recovery (.switching / .activePendingClear / .signedOutPendingClear)

    func testFinishPendingClearRecoversSwitchingToSignedOutAndKeepsDeviceID() throws {
        let store = KeyedFailureStore()
        let switching = SessionEpoch(id: "switch-1", phase: .switching)
        try seedAccountA(in: store, epoch: switching)
        let snapshots = SharedSnapshotStore(store: store)
        let vault = StoredSchoolVault(store: store)

        // While `.switching`: both snapshot and account are hidden.
        XCTAssertNil(try snapshots.loadSnapshot())
        let hidden = try XCTUnwrap(WidgetStoredData.read(snapshots: snapshots, vault: vault))
        XCTAssertNil(hidden.snapshot)
        XCTAssertNil(hidden.account)
        XCTAssertEqual(hidden.epoch, switching)

        // Fail deleting one credential first: epoch MUST remain `(switch-1, .switching)` and never activate.
        store.refusingDeletes = [.schoolPortal]
        XCTAssertThrowsError(try snapshots.finishPendingClear())
        XCTAssertEqual(try SessionEpochStore(store: store).read(), switching, "stays .switching while any credential remains")
        XCTAssertNotNil(try store.read(.schoolPortal))
        XCTAssertNil(try store.read(.schoolPassword), "other credentials deleted on first pass")
        XCTAssertNil(try store.read(.schoolEcykt))
        XCTAssertNil(try store.read(.schoolProfile))
        XCTAssertNotNil(try store.read(.schoolDevice), "device ID is preserved across .switching recovery")

        // Next pass: credential delete succeeds, snapshot write fails -> advances to `.signedOutPendingClear`.
        store.refusingDeletes = []
        store.refusingWrites = [.sharedSnapshot]
        XCTAssertThrowsError(try snapshots.finishPendingClear())
        XCTAssertNil(try store.read(.schoolPortal))
        XCTAssertEqual(try SessionEpochStore(store: store).read(), SessionEpoch(id: "switch-1", phase: .signedOutPendingClear))
        XCTAssertNil(try snapshots.loadSnapshot())

        // Final pass: snapshot write succeeds -> advances to `.signedOut`.
        store.refusingWrites = []
        try snapshots.finishPendingClear()
        XCTAssertEqual(try SessionEpochStore(store: store).read(), SessionEpoch(id: "switch-1", phase: .signedOut))
        XCTAssertNil(try snapshots.loadSnapshot())
        XCTAssertNotNil(try store.read(.schoolDevice))
    }

    func testSignOutStaysSwitchingWhenAnyCredentialDeleteFailsAndRecoversOffline() async throws {
        let store = KeyedFailureStore()
        try seedAccountA(in: store, epoch: SessionEpoch(id: "epoch-a", phase: .active))
        let h = Harness()
        let session = SchoolSession(portal: PortalClient(http: h.server.makeClient()),
                                    ecykt: EcyktClient(http: h.server.makeClient()),
                                    vault: StoredSchoolVault(store: store),
                                    now: h.clock.function,
                                    profileLock: InMemoryCommitLock())
        store.refusingDeletes = [.schoolPortal]
        do {
            try await session.signOut()
            XCTFail("expected SignOutFailure when schoolPortal deletion fails")
        } catch let failure as SchoolSession.SignOutFailure {
            XCTAssertEqual(failure.items, ["portalToken"])
        }
        let epochAfterFail = try XCTUnwrap(try SessionEpochStore(store: store).read())
        XCTAssertEqual(epochAfterFail.phase, .switching, "must stay .switching when any credential delete fails")
        XCTAssertNotEqual(epochAfterFail.id, "epoch-a")
        XCTAssertNil(try SharedSnapshotStore(store: store).loadSnapshot())
        XCTAssertNil(WidgetStoredData.read(snapshots: SharedSnapshotStore(store: store), vault: StoredSchoolVault(store: store))?.account)

        // Recovery via `finishPendingClear` finishes deleting portalToken and lands in `.signedOut`.
        store.refusingDeletes = []
        try SharedSnapshotStore(store: store).finishPendingClear()
        XCTAssertNil(try store.read(.schoolPortal))
        XCTAssertEqual(try SessionEpochStore(store: store).read(), SessionEpoch(id: epochAfterFail.id, phase: .signedOut))
    }

    func testSignOutFailsClosedWhenLockCannotBeAcquired() async throws {
        let store = KeyedFailureStore()
        let initialEpoch = SessionEpoch(id: "epoch-a", phase: .active)
        try seedAccountA(in: store, epoch: initialEpoch)
        let h = Harness()
        let session = SchoolSession(portal: PortalClient(http: h.server.makeClient()),
                                    ecykt: EcyktClient(http: h.server.makeClient()),
                                    vault: StoredSchoolVault(store: store),
                                    now: h.clock.function,
                                    profileLock: FailingSharedLock())
        store.forgetSteps()
        do {
            try await session.signOut()
            XCTFail("expected SignOutFailure when lock fails")
        } catch let failure as SchoolSession.SignOutFailure {
            XCTAssertEqual(failure.items, ["sessionEpoch"])
        }
        XCTAssertTrue(store.steps.isEmpty, "must not touch any credential or epoch without the lock")
        XCTAssertEqual(try SessionEpochStore(store: store).read(), initialEpoch)
        XCTAssertNotNil(try store.read(.schoolEcykt))
    }

    func testActivePendingClearRefreshStartsFromEmptyAndAdvancesToActive() async throws {
        let h = Harness()
        let epochB = SessionEpoch(id: "epoch-b", phase: .activePendingClear)
        // Store still has A's snapshot bytes, while credentials and epoch belong to B (`.activePendingClear`).
        try h.signedIn()
        try h.vault.saveSessionEpoch(epochB)
        try h.snapshots.saveSnapshot(snapshot(balance: balanceA, at: t0, epochID: "epoch-a"))

        // Before refresh: A's snapshot is unreadable, B's account is readable.
        XCTAssertNil(try h.snapshots.loadSnapshot())

        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok") // ¥7.90
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertTrue(report.snapshotSaved)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 790))
        XCTAssertEqual(report.snapshot.epochID, "epoch-b")
        XCTAssertEqual(try SessionEpochStore(store: h.store).read(), SessionEpoch(id: "epoch-b", phase: .active))
        XCTAssertEqual(try h.snapshots.loadSnapshot()?.card.value, Money(fen: 790))
    }

    func testSavePasswordIsRejectedInSwitchingAndSignedOutPhases() async throws {
        for phase in [SessionEpoch.Phase.switching, .signedOutPendingClear, .signedOut] {
            let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
            var h = Harness()
            h.passwordLogin = login
            try h.signedIn()
            try h.vault.saveAccount(SchoolAccount(account: "99100991"))
            try h.vault.saveSessionEpoch(SessionEpoch(id: "e-\(phase.rawValue)", phase: phase))
            do {
                try await h.session().savePassword("synthetic-pw-991", account: "99100991", owning: .unchecked)
                XCTFail("savePassword must reject phase \(phase)")
            } catch {
                XCTAssertEqual(error as? SchoolLoginFailure, .busy, "phase \(phase)")
            }
            XCTAssertTrue(login.calls.isEmpty, "must not call password login in phase \(phase)")
        }
    }

    func testPostWriteReadBackMismatchLeavesSwitchingAndThrows() async throws {
        /// Store that drops or mutates `.schoolEcykt` right after writing it so post-write read-back fails.
        final class CorruptingStore: SecureStore, @unchecked Sendable {
            private let base = InMemorySecureStore()
            private let lock = NSLock()
            private var corruptNextEcykt = false
            func armCorruptEcykt() { lock.withLock { corruptNextEcykt = true } }
            func read(_ key: StoreKey) throws -> Data? { try base.read(key) }
            func write(_ data: Data, for key: StoreKey) throws {
                let shouldCorrupt = lock.withLock {
                    if key == .schoolEcykt && corruptNextEcykt { corruptNextEcykt = false; return true }
                    return false
                }
                if shouldCorrupt {
                    var tampered = try JSONDecoder().decode(EcyktSession.self, from: data)
                    tampered.token = "TAMPERED-TOKEN"
                    try base.write(try JSONEncoder().encode(tampered), for: key)
                } else {
                    try base.write(data, for: key)
                }
            }
            func delete(_ key: StoreKey) throws { try base.delete(key) }
        }

        let store = CorruptingStore()
        try seedAccountA(in: store, epoch: SessionEpoch(id: "epoch-a", phase: .active))
        var h = Harness()
        h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "NEXT-TOKEN"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let http = h.server.makeClient()
        let session = SchoolSession(portal: PortalClient(http: http), ecykt: EcyktClient(http: http),
                                    vault: StoredSchoolVault(store: store), passwordLogin: h.passwordLogin,
                                    now: h.clock.function)
        store.armCorruptEcykt()
        do {
            _ = try await session.signIn(account: "99100992", password: "synthetic-pw-992", savePassword: false, owning: .unchecked)
            XCTFail("read-back verification must fail")
        } catch {
            XCTAssertTrue(error is StorageError)
        }
        let epoch = try XCTUnwrap(try SessionEpochStore(store: store).read())
        XCTAssertEqual(epoch.phase, .switching, "failed verification must never publish .activePendingClear")
        XCTAssertNotEqual(epoch.id, "epoch-a")
    }

    func testSamePersonSignInWithLegacyStaleMarkForcesNewEpochSwitch() async throws {
        let store = KeyedFailureStore()
        let vault = StoredSchoolVault(store: store)
        var sessionA = T.session()
        sessionA.cardUnionID = "TESTid00000000000000000000000001"
        try vault.saveEcyktSession(sessionA)
        try vault.savePortalToken(PortalToken("PORTAL"))
        try vault.saveAccount(SchoolAccount(account: "99100991"))
        try store.write(Data("{\"since\":0}".utf8), for: .sharedSnapshotStale)

        var h = Harness()
        h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "SAME-NEXT"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let http = h.server.makeClient()
        let session = SchoolSession(portal: PortalClient(http: http), ecykt: EcyktClient(http: http),
                                    vault: vault, passwordLogin: h.passwordLogin, now: h.clock.function)

        _ = try await session.signIn(account: "99100991", password: "synthetic-pw-991", savePassword: false, owning: .unchecked)
        XCTAssertEqual(try SessionEpochStore(store: store).read()?.phase, .activePendingClear,
                       "legacy stale mark forces a switch epoch even for the same account")
    }

    // MARK: 3. Cross-Process Epoch Fencing & Concurrency

    func testStaleRefreshCommitIsRejectedAfterEpochChanges() throws {
        let store = InMemorySecureStore()
        let epochA = SessionEpoch(id: "epoch-a", phase: .active)
        let epochB = SessionEpoch(id: "epoch-b", phase: .active)
        let snapshots = SharedSnapshotStore(store: store)
        try SessionEpochStore(store: store).write(epochB)
        let snapB = snapshot(balance: balanceB, at: t1, epochID: epochB.id)
        try snapshots.saveSnapshot(snapB)

        // Late refresh from epoch A attempts to commit under expectedEpoch = epochA.
        let snapA = snapshot(balance: balanceA, at: t1.addingTimeInterval(60), epochID: nil)
        let committed = try snapshots.commitSnapshot(snapA, expectedEpoch: epochA)
        XCTAssertNil(committed, "stale epoch commit must be rejected")
        XCTAssertEqual(try snapshots.loadSnapshot()?.card.value, balanceB, "B's snapshot is untouched")
        XCTAssertEqual(try SessionEpochStore(store: store).read(), epochB)
    }

    func testNilLeaseFileFailsClosedAcrossStackOperations() async throws {
        let store = InMemorySecureStore()
        try seedAccountA(in: store, epoch: SessionEpoch(id: "epoch-a", phase: .active))
        let h = Harness()
        let stack = SchoolRefreshStack(store: store, http: h.server.makeClient(), role: "app",
                                       leaseWait: 0.1, leaseFile: nil, diagnostic: { _ in })

        // 1. holdingLease fails closed with `.busy` (never runs body unlocked).
        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            func set() { lock.withLock { value = true } }
            var isSet: Bool { lock.withLock { value } }
        }
        let bodyRan = Flag()
        do {
            try await stack.refresher.holdingLease { _ in bodyRan.set() }
            XCTFail("holdingLease with nil leaseFile must fail closed")
        } catch {
            XCTAssertEqual(error as? SchoolLoginFailure, .busy)
        }
        XCTAssertFalse(bodyRan.isSet)

        // 2. signOut fails closed without touching credentials.
        do {
            try await stack.session.signOut()
            XCTFail("signOut with nil leaseFile must fail closed")
        } catch let failure as SchoolSession.SignOutFailure {
            XCTAssertEqual(failure.items, ["sessionEpoch"])
        }
        XCTAssertNotNil(try store.read(.schoolEcykt))

        // 3. forgetPassword fails closed without touching saved password.
        do {
            try await stack.session.forgetPassword(lockingWith: stack.refresher.commitLock)
            XCTFail("forgetPassword with nil leaseFile must fail closed")
        } catch {
            XCTAssertTrue(error is LeaseFile.Failure)
        }
        XCTAssertNotNil(try StoredSchoolVault(store: store).account()?.password)

        // 4. refresher.clear() fails closed.
        do {
            try await stack.refresher.clear()
            XCTFail("clear with nil leaseFile must fail closed")
        } catch {
            XCTAssertTrue(error is LeaseFile.Failure)
        }
    }

    // MARK: 4. Widget Double-Read Consistency & Pre-Completion Re-Check

    func testWidgetDoubleReadFailsClosedWhenEpochChangesOnBothAttempts() throws {
        /// Mutates `shared.sessionEpoch` on each read of `.sharedSessionEpoch` to simulate concurrent
        /// logout/switch landing between the first and second epoch reads.
        final class RacingEpochStore: SecureStore, @unchecked Sendable {
            private let base = InMemorySecureStore()
            private let lock = NSLock()
            private var epochReads = 0
            private let nextEpoch: @Sendable (Int) -> SessionEpoch?

            init(nextEpoch: @escaping @Sendable (Int) -> SessionEpoch?) { self.nextEpoch = nextEpoch }
            var epochReadCount: Int { lock.withLock { epochReads } }
            func read(_ key: StoreKey) throws -> Data? {
                let data = try base.read(key)
                if key == .sharedSessionEpoch {
                    let next: SessionEpoch? = lock.withLock {
                        epochReads += 1
                        return nextEpoch(epochReads)
                    }
                    if let next {
                        try base.write(try JSONEncoder().encode(next), for: .sharedSessionEpoch)
                    }
                }
                return data
            }
            func write(_ data: Data, for key: StoreKey) throws { try base.write(data, for: key) }
            func delete(_ key: StoreKey) throws { try base.delete(key) }
        }

        // Case 1: epoch changes on every read, so both attempt 1 and attempt 2 see epochBefore != epochAfter.
        let alwaysRacing = RacingEpochStore { readNumber in
            SessionEpoch(id: "e-\(readNumber + 1)", phase: readNumber.isMultiple(of: 2) ? .signedOut : .switching)
        }
        try seedAccountA(in: alwaysRacing, epoch: SessionEpoch(id: "e-1", phase: .active))
        let result = WidgetStoredData.read(snapshots: SharedSnapshotStore(store: alwaysRacing),
                                           vault: StoredSchoolVault(store: alwaysRacing))
        XCTAssertNil(result, "unstable epoch across both attempts must fail closed")

        // Case 2: epoch mutates during attempt 1, then stabilizes as `.signedOut` on attempt 2.
        let settlesOnRetry = RacingEpochStore { readNumber in
            readNumber == 1 ? SessionEpoch(id: "e-2", phase: .signedOut) : nil
        }
        try seedAccountA(in: settlesOnRetry, epoch: SessionEpoch(id: "e-1", phase: .active))
        let settled = try XCTUnwrap(WidgetStoredData.read(snapshots: SharedSnapshotStore(store: settlesOnRetry),
                                                          vault: StoredSchoolVault(store: settlesOnRetry)))
        XCTAssertGreaterThanOrEqual(settlesOnRetry.epochReadCount, 4, "must retry after attempt 1 mismatch")
        XCTAssertEqual(settled.epoch, SessionEpoch(id: "e-2", phase: .signedOut))
        XCTAssertNil(settled.snapshot)
        XCTAssertNil(settled.account)
    }

    func testWidgetVerifiedForCompletionDiscardsStaleEntryOnConcurrentLogoutOrSwitch() throws {
        let store = KeyedFailureStore()
        let epochA = SessionEpoch(id: "epoch-a", phase: .active)
        try seedAccountA(in: store, epoch: epochA)
        let snapshots = SharedSnapshotStore(store: store)
        let vault = StoredSchoolVault(store: store)

        let storedA = try XCTUnwrap(WidgetStoredData.read(snapshots: snapshots, vault: vault))
        let initialA = WidgetDrawChoice.choose(storedA)
        let drawnA = try XCTUnwrap(storedA.snapshot)

        // 1. No change: draws A's snapshot.
        let ok = WidgetDrawChoice.verifiedForCompletion(initial: initialA, initialEpoch: epochA, drawn: drawnA,
                                                        snapshots: snapshots, vault: vault)
        XCTAssertEqual(ok.drawn?.card.value, balanceA)

        // 2. Concurrent sign-out (`.signedOut`) before completion: discards A's snapshot and account.
        try vault.saveSessionEpoch(SessionEpoch(id: "epoch-out", phase: .signedOut))
        let signedOut = WidgetDrawChoice.verifiedForCompletion(initial: initialA, initialEpoch: epochA, drawn: drawnA,
                                                               snapshots: snapshots, vault: vault)
        XCTAssertEqual(signedOut.choice, .draw(snapshot: nil, account: nil))
        XCTAssertNil(signedOut.drawn)

        // 3. Concurrent switch to B (`.activePendingClear`): discards A's snapshot, keeps B's account.
        let epochBPending = SessionEpoch(id: "epoch-b", phase: .activePendingClear)
        try vault.saveSessionEpoch(epochBPending)
        try vault.saveAccount(SchoolAccount(account: "99100992"))
        let switchingB = WidgetDrawChoice.verifiedForCompletion(initial: initialA, initialEpoch: epochA, drawn: drawnA,
                                                                snapshots: snapshots, vault: vault)
        XCTAssertEqual(switchingB.choice, .draw(snapshot: nil, account: SchoolAccount(account: "99100992")))
        XCTAssertNil(switchingB.drawn)

        // 4. Concurrent switch completed to B (`.active` with B's snapshot): draws B's snapshot, never A's.
        let epochB = SessionEpoch(id: "epoch-b", phase: .active)
        let snapB = snapshot(balance: balanceB, at: t1, epochID: epochB.id)
        try snapshots.saveSnapshot(snapB)
        try vault.saveSessionEpoch(epochB)
        let activeB = WidgetDrawChoice.verifiedForCompletion(initial: initialA, initialEpoch: epochA, drawn: drawnA,
                                                             snapshots: snapshots, vault: vault)
        XCTAssertEqual(activeB.drawn?.card.value, balanceB)
        XCTAssertEqual(activeB.choice, .draw(snapshot: snapB, account: SchoolAccount(account: "99100992")))

        // 5. Keychain becomes unreadable right before completion: fails closed with `.noNumbers`.
        store.refusingReads = [.sharedSessionEpoch]
        let unreadable = WidgetDrawChoice.verifiedForCompletion(initial: initialA, initialEpoch: epochA, drawn: drawnA,
                                                                snapshots: snapshots, vault: vault)
        XCTAssertEqual(unreadable.choice, .noNumbers(retryAfter: WidgetStoredData.unreadableRetry))
        XCTAssertNil(unreadable.drawn)
    }
}
