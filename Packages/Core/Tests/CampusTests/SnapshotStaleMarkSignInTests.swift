//
//  SnapshotStaleMarkSignInTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core
import CoreTestSupport

/// Someone else (or someone not known to be the same person) signs in, or 退出登录: the shared
/// snapshot is marked first (`shared.snapshotStale`), in the same locked step as the
/// credentials and before any of them changes, so the previous person's numbers are never shown
/// again even when clearing them fails. A mark that can't be written changes nobody.
final class SnapshotStaleMarkSignInTests: XCTestCase {
    static let otherCard = SchoolAccountSwitchTests.otherCard
    static let sameCard = "TESTid00000000000000000000000001"
    let previous = Money(fen: 4321)

    /// Signed in as somebody whose card is `card`, with a dorm, an account, a login device and
    /// their numbers in the shared snapshot, all on `store`.
    func seed(_ store: SecureStore, card: String) throws {
        let vault = StoredSchoolVault(store: store)
        var session = T.session(); session.cardUnionID = card
        try vault.saveEcyktSession(session)
        try vault.savePortalToken(PortalToken("PORTAL"))
        try vault.saveProfile(SchoolProfile(residence: PortalResidence(raw: "星湖校区98栋8号1层881房"), meter: Harness.roomBinding))
        try vault.saveAccount(SchoolAccount(account: "99100991"))
        try vault.saveLoginDeviceID("99000000000000000000000000000991")
        var s = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: Date(timeIntervalSince1970: 1_793_000_000)))
        s = SchoolSnapshotReducer.reduce(s, .balance(.success(previous), at: Date(timeIntervalSince1970: 1_793_000_000)))
        try SharedSnapshotStore(store: store).saveSnapshot(s)
    }

    func harness(byForm: Bool) throws -> Harness {
        var h = Harness()
        h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        if byForm {
            h.server.serve(try T.eCardWithTicket())
            h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "NEXT-TOKEN"))
        }
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        return h
    }

    func makeSession(_ h: Harness, on store: SecureStore) -> SchoolSession {
        let http = h.server.makeClient()
        return SchoolSession(portal: PortalClient(http: http), ecykt: EcyktClient(http: http), vault: StoredSchoolVault(store: store),
                             passwordLogin: h.passwordLogin, now: h.clock.function)
    }

    /// The sign-in as the app runs it, returning the clean-ups it asked for (unconfirmed or not).
    func signIn(_ session: SchoolSession, byForm: Bool, account: String = "99100992",
                cleanUps: inout [Bool], changes: inout Int) async throws {
        var asked: [Bool] = [], changed = 0
        defer { cleanUps += asked; changes += changed }
        _ = try await SchoolSession.signingIn(on: session, {
            if byForm {
                return try await session.signIn(account: account, password: "synthetic-pw-992", savePassword: false, owning: .unchecked)
            }
            return try await session.adoptWebState(try FixtureLoader.csaLoginState().encoded(), owning: .unchecked)
        }, changed: { changed += 1 }, cleanUp: { unconfirmed, _ in asked.append(unconfirmed) })
    }

    func testASwitchMarksTheSnapshotBeforeItsOtherWrites() async throws {
        for byForm in [false, true] {
            let h = try harness(byForm: byForm)
            let store = KeyedFailureStore()
            try seed(store, card: Self.otherCard)
            store.forgetSteps()
            // Refused both ways: the web sign-in only deletes the profile, the form's writes it.
            store.refusingWrites = [.schoolProfile]
            store.refusingDeletes = [.schoolProfile]
            let session = makeSession(h, on: store)
            let before = await session.personStamp()
            var cleanUps: [Bool] = [], changes = 0
            do {
                try await signIn(session, byForm: byForm, cleanUps: &cleanUps, changes: &changes)
                XCTFail("byForm \(byForm): the profile write was meant to fail")
            } catch {
                XCTAssertTrue(error is StorageError, "byForm \(byForm): \(error)")
            }
            let steps = store.steps
            let mark = try XCTUnwrap(steps.firstIndex(of: "write shared.sessionEpoch"), "byForm \(byForm): \(steps)")
            XCTAssertFalse(steps[..<mark].contains { $0.contains(" school.") || $0.hasSuffix(" shared.snapshot") },
                           "byForm \(byForm): the switching epoch goes before anything else: \(steps)")
            XCTAssertNil(try store.read(.sharedSnapshotStale), "byForm \(byForm): legacy stale marker is never written")
            XCTAssertEqual(try SessionEpochStore(store: store).read()?.phase, .switching, "byForm \(byForm): stays in .switching after partial failure")
            XCTAssertNil(try SharedSnapshotStore(store: store).loadSnapshot(), "byForm \(byForm): the previous numbers are hidden")
            XCTAssertEqual(cleanUps, [true], "byForm \(byForm): the clean-up still runs")
            let after = await session.personStamp()
            XCTAssertNotEqual(after, before, "byForm \(byForm): the person changed")
        }
    }

    func testAMarkThatCannotBeWrittenChangesNobody() async throws {
        for byForm in [false, true] {
            let h = try harness(byForm: byForm)
            let store = KeyedFailureStore()
            try seed(store, card: Self.otherCard)
            let credentials = try StoredSchoolVault(store: store).credentialBytes()
            let profile = try store.read(.schoolProfile)
            store.forgetSteps()
            store.refusingWrites = [.sharedSessionEpoch]
            let session = makeSession(h, on: store)
            let before = await session.personStamp()
            var cleanUps: [Bool] = [], changes = 0
            do {
                try await signIn(session, byForm: byForm, cleanUps: &cleanUps, changes: &changes)
                XCTFail("byForm \(byForm): the epoch could not be written")
            } catch {
                XCTAssertTrue(error is StorageError, "byForm \(byForm): \(error)")
            }
            XCTAssertFalse(store.steps.contains { $0.contains(" school.") || $0.contains(" shared.snapshot") },
                           "byForm \(byForm): nothing was written or deleted: \(store.steps)")
            XCTAssertEqual(try StoredSchoolVault(store: store).credentialBytes(), credentials, "byForm \(byForm)")
            XCTAssertEqual(try store.read(.schoolProfile), profile, "byForm \(byForm)")
            let after = await session.personStamp()
            XCTAssertEqual(after, before, "byForm \(byForm): nobody changed")
            XCTAssertEqual(cleanUps, [], "byForm \(byForm)")
            XCTAssertEqual(changes, 0, "byForm \(byForm)")
            XCTAssertEqual(try SharedSnapshotStore(store: store).loadSnapshot()?.card.value, previous,
                           "byForm \(byForm): still the signed-in person's own numbers")
        }
    }

    func testASamePersonSignInLeavesNoMark() async throws {
        for byForm in [false, true] {
            let h = try harness(byForm: byForm)
            let store = KeyedFailureStore()
            try seed(store, card: Self.sameCard)
            let session = makeSession(h, on: store)
            var cleanUps: [Bool] = [], changes = 0
            try await signIn(session, byForm: byForm, account: "99100991", cleanUps: &cleanUps, changes: &changes)
            XCTAssertEqual(cleanUps, [], "byForm \(byForm): the same person")
            XCTAssertNil(try store.read(.sharedSnapshotStale), "byForm \(byForm)")
            XCTAssertNil(try SessionEpochStore(store: store).read(), "byForm \(byForm): same person on 0.11.5 keeps snapshot readable")
            XCTAssertEqual(try SharedSnapshotStore(store: store).loadSnapshot()?.card.value, previous, "byForm \(byForm): their numbers stay")
        }
    }

    func testAWebSignInOfAnotherPersonMarksTheSnapshot() async throws {
        let h = try harness(byForm: false)
        let store = KeyedFailureStore()
        try seed(store, card: Self.otherCard)
        let session = makeSession(h, on: store)
        var cleanUps: [Bool] = [], changes = 0
        try await signIn(session, byForm: false, cleanUps: &cleanUps, changes: &changes)
        XCTAssertEqual(cleanUps, [false], "a confirmed switch")
        XCTAssertNil(try store.read(.sharedSnapshotStale), "legacy stale marker is never written")
        XCTAssertEqual(try SessionEpochStore(store: store).read()?.phase, .activePendingClear)
        XCTAssertNil(try SharedSnapshotStore(store: store).loadSnapshot())
        XCTAssertNil(WidgetStoredData.read(snapshots: SharedSnapshotStore(store: store), vault: StoredSchoolVault(store: store))?.snapshot)
    }

    /// Nothing tells whether it is the same person (the stored card session no longer decodes):
    /// transitions through a new epoch.
    func testASignInThatCannotTellThePersonMarksTheSnapshot() async throws {
        let h = try harness(byForm: false)
        let store = KeyedFailureStore()
        try seed(store, card: Self.otherCard)
        try store.write(Data("not json".utf8), for: .schoolEcykt)
        try store.write(Data("not json".utf8), for: .schoolPassword)
        let session = makeSession(h, on: store)
        var cleanUps: [Bool] = [], changes = 0
        try await signIn(session, byForm: false, cleanUps: &cleanUps, changes: &changes)
        XCTAssertEqual(cleanUps, [true], "unconfirmed")
        XCTAssertNil(try store.read(.sharedSnapshotStale), "legacy stale marker is never written")
        XCTAssertEqual(try SessionEpochStore(store: store).read()?.phase, .activePendingClear)
        XCTAssertNil(try SharedSnapshotStore(store: store).loadSnapshot())
    }

    // MARK: 退出登录

    func makeSignOuts(_ h: Harness, on store: SecureStore) -> (SchoolSession, SnapshotRefresher, SchoolSignOut) {
        let session = makeSession(h, on: store)
        let refresher = SnapshotRefresher(school: session, store: SharedSnapshotStore(store: store))
        return (session, refresher, SchoolSignOut(session: session, refresher: refresher))
    }

    static let credentialKeys: [StoreKey] = [.schoolPassword, .schoolPortal, .schoolEcykt, .schoolProfile, .schoolDevice]

    func testASignOutThatCannotMarkDeletesNothing() async throws {
        let h = Harness()
        let store = KeyedFailureStore()
        try seed(store, card: Self.otherCard)
        let stored = try Self.credentialKeys.map { try store.read($0) }
        store.refusingWrites = [.sharedSessionEpoch, .sharedSnapshot]
        let (session, _, signOuts) = makeSignOuts(h, on: store)
        do {
            try await session.signOut()
            XCTFail("the epoch could not be written")
        } catch let failure as SchoolSession.SignOutFailure {
            XCTAssertEqual(failure.items, ["sessionEpoch"])
        }
        XCTAssertEqual(try Self.credentialKeys.map { try store.read($0) }, stored, "every credential is as it was")

        let deleted = await signOuts.start().value
        XCTAssertFalse(deleted)
        XCTAssertEqual(try Self.credentialKeys.map { try store.read($0) }, stored, "still as it was")
    }

    func testASignOutWhoseSnapshotClearFailsKeepsTheMarkAndHides() async throws {
        let h = Harness()
        let store = KeyedFailureStore()
        try seed(store, card: Self.otherCard)
        store.refusingWrites = [.sharedSnapshot]
        let (_, refresher, signOuts) = makeSignOuts(h, on: store)
        let deleted = await signOuts.start().value
        XCTAssertFalse(deleted, "the snapshot could not be cleared")
        for key in Self.credentialKeys { XCTAssertNil(try store.read(key), "\(key.rawValue) deleted all the same") }
        XCTAssertNil(try store.read(.sharedSnapshotStale), "legacy stale marker is never written")
        XCTAssertEqual(try SessionEpochStore(store: store).read()?.phase, .signedOutPendingClear, "stays pending clear")
        XCTAssertNotNil(try store.read(.sharedSnapshot), "the old bytes could not be replaced")
        XCTAssertEqual(refresher.latest(), .empty)
        XCTAssertNil(try SharedSnapshotStore(store: store).loadSnapshot(), "read again (a relaunch)")
        XCTAssertNil(WidgetStoredData.read(snapshots: SharedSnapshotStore(store: store), vault: StoredSchoolVault(store: store))?.snapshot)
    }

    func testANormalSignOutRemovesTheMarkOnlyAfterTheEmptySnapshotIsSaved() async throws {
        let h = Harness()
        let store = KeyedFailureStore()
        try seed(store, card: Self.otherCard)
        store.forgetSteps()
        let (_, _, signOuts) = makeSignOuts(h, on: store)
        let deleted = await signOuts.start().value
        XCTAssertTrue(deleted)
        let steps = store.steps
        let pending = try XCTUnwrap(steps.firstIndex(of: "write shared.sessionEpoch"))
        let empty = try XCTUnwrap(steps.firstIndex(of: "write shared.snapshot"))
        let finalEpoch = try XCTUnwrap(steps.lastIndex(of: "write shared.sessionEpoch"))
        XCTAssertFalse(steps[..<pending].contains { $0.contains(" school.") }, "the epoch before any credential goes: \(steps)")
        XCTAssertLessThan(empty, finalEpoch)
        XCTAssertNil(try store.read(.sharedSnapshotStale))
        XCTAssertEqual(try SessionEpochStore(store: store).read()?.phase, .signedOut)
        XCTAssertNil(try SharedSnapshotStore(store: store).loadSnapshot())

        let failing = KeyedFailureStore()
        try seed(failing, card: Self.otherCard)
        failing.forgetSteps()
        failing.refusingWrites = [.sharedSnapshot]
        let (_, _, again) = makeSignOuts(h, on: failing)
        let failed = await again.start().value
        XCTAssertFalse(failed)
        XCTAssertEqual(try SessionEpochStore(store: failing).read()?.phase, .signedOutPendingClear)
    }
}
