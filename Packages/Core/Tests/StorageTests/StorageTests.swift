import XCTest
import Core
import os

/// SecItem backend with the device's access-group rules (no host Keychain):
/// - every item lives in exactly one group;
/// - add without a group lands in the first group of the entitlement list;
/// - copy without a group searches every entitled group (in entitlement order); update and
///   delete without a group touch every match;
/// - a group not in the entitlement list answers `errSecMissingEntitlement`.
final class FakeKeychain: KeychainBackend, @unchecked Sendable {
    struct Key: Hashable { var service: String; var group: String }
    private let lock = NSLock()
    /// This process's `keychain-access-groups`, team prefix resolved. First = default group.
    var entitlements: [String]
    var items: [Key: Data] = [:]
    var accessibility: [Key: StoreKey.Accessibility] = [:]
    var readStatus: Int32? = nil
    /// Forced status per call, e.g. `"add <group>"` or `"delete <group>"`.
    var failing: [String: Int32] = [:]
    var calls: [String] = [] { didSet { if let call = calls.last { afterCall?(call) } } }
    /// Runs inside each call after it is recorded, e.g. to make a later step fail.
    var afterCall: ((String) -> Void)?

    static let shared = "TEAMID1234.com.beamjason.xiaorichang.shared"
    static let app = "TEAMID1234.com.beamjason.xiaorichang"

    init(entitlements: [String] = [FakeKeychain.shared]) { self.entitlements = entitlements }

    private func groups(_ g: String?) -> [String]? {
        guard let g else { return entitlements }
        return entitlements.contains(g) ? [g] : nil
    }

    func copy(service: String, account: String, accessGroup: String?) -> (status: Int32, data: Data?) {
        lock.withLock {
            calls.append("copy \(accessGroup ?? "-")")
            if let readStatus { return (readStatus, nil) }
            if let forced = failing["copy \(accessGroup ?? "-")"] { return (forced, nil) }
            guard let gs = groups(accessGroup) else { return (KeychainStatus.missingEntitlement, nil) }
            for g in gs { if let d = items[Key(service: service, group: g)] { return (KeychainStatus.success, d) } }
            return (KeychainStatus.itemNotFound, nil)
        }
    }
    func add(service: String, account: String, accessGroup: String?, accessibility a: StoreKey.Accessibility, data: Data) -> Int32 {
        lock.withLock {
            calls.append("add \(accessGroup ?? "-")")
            if let forced = failing["add \(accessGroup ?? "-")"] { return forced }
            guard let g = groups(accessGroup)?.first else { return KeychainStatus.missingEntitlement }
            let k = Key(service: service, group: g)
            if items[k] != nil { return KeychainStatus.duplicateItem }
            items[k] = data; accessibility[k] = a
            return KeychainStatus.success
        }
    }
    func update(service: String, account: String, accessGroup: String?, accessibility a: StoreKey.Accessibility, data: Data) -> Int32 {
        lock.withLock {
            calls.append("update \(accessGroup ?? "-")")
            if let forced = failing["update \(accessGroup ?? "-")"] { return forced }
            guard let gs = groups(accessGroup) else { return KeychainStatus.missingEntitlement }
            let keys = gs.map { Key(service: service, group: $0) }.filter { items[$0] != nil }
            guard !keys.isEmpty else { return KeychainStatus.itemNotFound }
            for k in keys { items[k] = data; accessibility[k] = a }
            return KeychainStatus.success
        }
    }
    func delete(service: String, account: String, accessGroup: String?) -> Int32 {
        lock.withLock {
            calls.append("delete \(accessGroup ?? "-")")
            if let forced = failing["delete \(accessGroup ?? "-")"] { return forced }
            guard let gs = groups(accessGroup) else { return KeychainStatus.missingEntitlement }
            let removed = gs.compactMap { items.removeValue(forKey: Key(service: service, group: $0)) }
            return removed.isEmpty ? KeychainStatus.itemNotFound : KeychainStatus.success
        }
    }
}

/// Another process's view of the same keychain, with its own entitlements.
final class FakeKeychainView: KeychainBackend, @unchecked Sendable {
    let base: FakeKeychain
    let entitlements: [String]
    init(_ base: FakeKeychain, entitlements: [String]) { self.base = base; self.entitlements = entitlements }
    private func with<T>(_ body: () -> T) -> T {
        let saved = base.entitlements
        base.entitlements = entitlements
        defer { base.entitlements = saved }
        return body()
    }
    func copy(service: String, account: String, accessGroup: String?) -> (status: Int32, data: Data?) { with { base.copy(service: service, account: account, accessGroup: accessGroup) } }
    func add(service: String, account: String, accessGroup: String?, accessibility: StoreKey.Accessibility, data: Data) -> Int32 { with { base.add(service: service, account: account, accessGroup: accessGroup, accessibility: accessibility, data: data) } }
    func update(service: String, account: String, accessGroup: String?, accessibility: StoreKey.Accessibility, data: Data) -> Int32 { with { base.update(service: service, account: account, accessGroup: accessGroup, accessibility: accessibility, data: data) } }
    func delete(service: String, account: String, accessGroup: String?) -> Int32 { with { base.delete(service: service, account: account, accessGroup: accessGroup) } }
}

final class KeychainStoreTests: XCTestCase {
    let group = "TEAMID1234.com.beamjason.xiaorichang.shared"

    func testNames() {
        XCTAssertEqual(StoreKey.schoolEcykt.service, "com.beamjason.xiaorichang.school.ecykt.v1")
        XCTAssertEqual(StoreKey.sharedSnapshot.service, "com.beamjason.xiaorichang.shared.snapshot.v1")
        XCTAssertEqual(StoreKey.account, "default")
        XCTAssertEqual(StoreKey.schoolPortal.accessibility, .afterFirstUnlockThisDeviceOnly)
        XCTAssertEqual(StoreKey.schoolEcykt.accessibility, .afterFirstUnlockThisDeviceOnly)
        XCTAssertEqual(StoreKey.allCases.filter(\.isShared),
                       [.schoolPortal, .schoolEcykt, .schoolProfile, .schoolPassword, .schoolDevice, .sharedSnapshot, .sharedReminderLines,
                        .sharedRefreshLease, .sharedCredentialLog, .sharedResetMarker])
        XCTAssertEqual(StoreKey.schoolPassword.accessibility, .afterFirstUnlockThisDeviceOnly)
        XCTAssertEqual(PreferenceKey.reminder("card"), "xrc.reminder.card")
        XCTAssertEqual(PreferenceKey.laundryAckFailedOrder, "xrc.laundry.ackFailedOrder")
        XCTAssertEqual(SharedSnapshotStore.widgetKind, "XiaoRiChangBalances")
    }

    /// Installed builds already wrote these names; renaming one would lose the item.
    func testRemainingItemsKeepTheirStoredNames() {
        XCTAssertEqual(StoreKey.schoolPortal.service, "com.beamjason.xiaorichang.school.portal.v1")
        XCTAssertEqual(StoreKey.schoolProfile.service, "com.beamjason.xiaorichang.school.profile.v1")
        XCTAssertEqual(StoreKey.laundryAccount.service, "com.beamjason.xiaorichang.laundry.account.v1")
        XCTAssertEqual(StoreKey.laundryCheckout.service, "com.beamjason.xiaorichang.laundry.checkout.v1")
        XCTAssertEqual(StoreKey.sharedReminderLines.service, "com.beamjason.xiaorichang.shared.reminderLines.v1")
        XCTAssertEqual(PreferenceKey.schoolLaundry, "xrc.laundry.school")
        XCTAssertEqual(StoreKey.schoolPassword.service, "com.beamjason.xiaorichang.school.password.v1")
        XCTAssertEqual(StoreKey.schoolDevice.service, "com.beamjason.xiaorichang.school.device.v1")
        XCTAssertEqual(StoreKey.sharedRefreshLease.service, "com.beamjason.xiaorichang.shared.refreshLease.v1")
        XCTAssertEqual(StoreKey.sharedCredentialLog.service, "com.beamjason.xiaorichang.shared.credentialLog.v1")
        XCTAssertEqual(StoreKey.sharedResetMarker.service, "com.beamjason.xiaorichang.shared.resetMarker.v1")
        XCTAssertEqual(StoreKey.allCases.count, 14, "a new item needs its stored name pinned here")
    }

    /// The Swift names say shower; the stored names stay what installed builds already wrote.
    func testShowerItemsKeepTheirStoredNames() {
        XCTAssertEqual(StoreKey.showerBinding.service, "com.beamjason.xiaorichang.water.binding.v1")
        XCTAssertEqual(StoreKey.showerSession.service, "com.beamjason.xiaorichang.water.session.v1")
        XCTAssertEqual(PreferenceKey.showerNeedsResidenceReview, "xrc.water.needsResidenceReview")
    }

    let app = FakeKeychain.app

    /// The app process: private group first, then shared.
    func appKeychain() -> FakeKeychain { FakeKeychain(entitlements: [FakeKeychain.app, FakeKeychain.shared]) }
    func appStore(_ kc: FakeKeychain) -> KeychainSecureStore { KeychainSecureStore(backend: kc, accessGroup: group, privateGroup: app) }
    func key(_ k: StoreKey, _ g: String) -> FakeKeychain.Key { .init(service: k.service, group: g) }

    /// Replace only updates: an item deleted by another process is not added back.
    func testReplaceNeverAddsAnItem() throws {
        let kc = appKeychain()
        let store = appStore(kc)
        XCTAssertFalse(try store.replace(Data("x".utf8), for: .sharedRefreshLease))
        XCTAssertNil(kc.items[key(.sharedRefreshLease, group)])
        XCTAssertFalse(kc.calls.contains { $0.hasPrefix("add") })
        try store.write(Data("a".utf8), for: .sharedRefreshLease)
        XCTAssertTrue(try store.replace(Data("b".utf8), for: .sharedRefreshLease))
        XCTAssertEqual(kc.items[key(.sharedRefreshLease, group)], Data("b".utf8))
    }

    /// An item a fallback create left without a group is still found and replaced.
    func testReplaceFindsAnItemOutsideTheGroup() throws {
        let kc = appKeychain()
        let store = appStore(kc)
        kc.failing["update \(group)"] = KeychainStatus.missingEntitlement
        kc.items[key(.sharedRefreshLease, app)] = Data("a".utf8)
        XCTAssertTrue(try store.replace(Data("b".utf8), for: .sharedRefreshLease))
        XCTAssertEqual(kc.items[key(.sharedRefreshLease, app)], Data("b".utf8))
    }

    func testReplaceReportsOtherFailures() {
        let kc = appKeychain()
        kc.failing["update \(group)"] = -25308
        XCTAssertThrowsError(try appStore(kc).replace(Data("b".utf8), for: .sharedRefreshLease))
    }

    func testSharedItemsUseAccessGroupCredentialsNever() throws {
        let kc = appKeychain()
        let store = appStore(kc)
        try store.write(Data("s".utf8), for: .sharedSnapshot)
        try store.write(Data("c".utf8), for: .showerBinding)
        XCTAssertEqual(kc.items[key(.sharedSnapshot, group)], Data("s".utf8))
        XCTAssertEqual(kc.items[key(.showerBinding, app)], Data("c".utf8))
        XCTAssertNil(kc.items[key(.showerBinding, group)])
        XCTAssertFalse(store.isUsingFallback)
        XCTAssertEqual(try store.read(.sharedSnapshot), Data("s".utf8))
        // Overwrite goes through update.
        try store.write(Data("s2".utf8), for: .sharedSnapshot)
        XCTAssertEqual(try store.read(.sharedSnapshot), Data("s2".utf8))
    }

    /// Hot-water and laundry items never enter the group the widget can read, through the
    /// vaults that write them.
    func testShowerAndLaundryItemsNeverEnterTheSharedGroup() throws {
        let never: [StoreKey] = [.showerBinding, .showerSession, .laundryAccount, .laundryCheckout]
        for k in never { XCTAssertFalse(k.isShared, k.rawValue) }
        let kc = appKeychain()
        let store = appStore(kc)
        for k in never { try store.write(Data(k.rawValue.utf8), for: k) }
        for k in never {
            XCTAssertNil(kc.items[key(k, group)], k.rawValue)
            XCTAssertEqual(kc.items[key(k, app)], Data(k.rawValue.utf8), k.rawValue)
        }
        // The widget process (shared group only) cannot see them.
        let widget = KeychainSecureStore(backend: FakeKeychainView(kc, entitlements: [group]), accessGroup: group)
        for k in never { XCTAssertNil(try widget.read(k), k.rawValue) }
    }

    /// Re-signed IPA without the keychain-access-groups entitlement: fall back to no group.
    func testFallsBackWhenGroupWriteFails() throws {
        let kc = FakeKeychain(entitlements: ["TEAMID1234.com.example.resigned"])
        let store = appStore(kc)
        try store.write(Data("s".utf8), for: .sharedSnapshot)
        XCTAssertTrue(store.isUsingFallback)
        XCTAssertEqual(kc.items[key(.sharedSnapshot, "TEAMID1234.com.example.resigned")], Data("s".utf8))
        XCTAssertEqual(try store.read(.sharedSnapshot), Data("s".utf8))
        try store.write(Data("w".utf8), for: .showerBinding)
        XCTAssertEqual(try store.read(.showerBinding), Data("w".utf8))
        // Later writes skip the group entirely.
        kc.calls = []
        try store.write(Data("t".utf8), for: .sharedReminderLines)
        XCTAssertEqual(kc.calls, ["add -"])
        try store.delete(.sharedSnapshot)
        XCTAssertNil(try store.read(.sharedSnapshot))
    }

    /// The widget reads the school session and profile through the same access group.
    func testSchoolSessionAndProfileUseTheSharedGroup() throws {
        let kc = appKeychain()
        let vault = StoredSchoolVault(store: appStore(kc))
        try vault.saveEcyktSession(EcyktSession(token: "t", syscustid: "s"))
        try vault.saveProfile(SchoolProfile(residence: PortalResidence(raw: "示例校区99栋9号1层991房")))
        try vault.savePortalToken(PortalToken("p"))
        try vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try vault.saveLoginDeviceID("99000000000000000000000000000991")
        XCTAssertNotNil(kc.items[key(.schoolEcykt, group)])
        XCTAssertNotNil(kc.items[key(.schoolPassword, group)], "the widget will sign in again with the saved password")
        XCTAssertEqual(kc.accessibility[key(.schoolPassword, group)], .afterFirstUnlockThisDeviceOnly)
        XCTAssertNotNil(kc.items[key(.schoolDevice, group)], "the widget's password login uses the same browser id")
        XCTAssertNil(kc.items[key(.schoolDevice, app)])
        XCTAssertNotNil(kc.items[key(.schoolProfile, group)])
        XCTAssertEqual(kc.accessibility[key(.schoolEcykt, group)], .afterFirstUnlockThisDeviceOnly,
                       "background and widget reads work while the phone is locked")
        XCTAssertNotNil(kc.items[key(.schoolPortal, group)], "the widget renews the card session with it")
        XCTAssertNil(kc.items[key(.schoolPortal, app)])
        XCTAssertEqual(kc.accessibility[key(.schoolPortal, group)], .afterFirstUnlockThisDeviceOnly)
        // The widget process (shared group only) reads the same session.
        let widget = StoredSchoolVault(store: KeychainSecureStore(backend: FakeKeychainView(kc, entitlements: [group]), accessGroup: group))
        XCTAssertEqual(try widget.ecyktSession()?.syscustid, "s")
        XCTAssertEqual(try widget.account()?.usablePassword, "synthetic-pw-991")
        XCTAssertEqual(try widget.loginDeviceID(), "99000000000000000000000000000991")
        XCTAssertEqual(try widget.portalToken()?.value, "p")
    }

    /// An item the app wrote before it was pinned to the group (default group) is still read.
    func testSchoolSessionWrittenWithoutGroupStillReads() throws {
        let kc = FakeKeychain(entitlements: ["TEAMID1234.com.example.resigned"])
        kc.items[key(.schoolEcykt, "TEAMID1234.com.example.resigned")] = try JSONEncoder().encode(EcyktSession(token: "t", syscustid: "old"))
        let vault = StoredSchoolVault(store: appStore(kc))
        XCTAssertEqual(try vault.ecyktSession()?.syscustid, "old")
    }

    /// The fake follows the device: a write without a group lands in the first entitlement group.
    func testFakeWritesWithoutGroupLandInTheFirstGroup() throws {
        let kc = appKeychain()
        let store = KeychainSecureStore(backend: kc, accessGroup: nil)
        try store.write(Data("x".utf8), for: .showerBinding)
        XCTAssertEqual(kc.items[key(.showerBinding, app)], Data("x".utf8))
        XCTAssertNil(kc.items[key(.showerBinding, group)])
    }

    /// Items an older build wrote into the shared group (then the only one) move to the private
    /// group; the binding and sessions stay readable throughout.
    func testMigrationMovesPrivateItemsOutOfTheSharedGroup() throws {
        let kc = appKeychain()
        let moved: [StoreKey] = [.showerBinding, .showerSession, .laundryAccount, .laundryCheckout]
        for k in moved + [.schoolEcykt, .sharedSnapshot] { kc.items[key(k, group)] = Data(k.rawValue.utf8) }
        let store = appStore(kc)
        XCTAssertEqual(store.migrateItemGroups(), [])
        for k in moved {
            XCTAssertNil(kc.items[key(k, group)], k.rawValue)
            XCTAssertEqual(kc.items[key(k, app)], Data(k.rawValue.utf8), k.rawValue)
            XCTAssertEqual(kc.accessibility[key(k, app)], k.accessibility, k.rawValue)
            XCTAssertEqual(try store.read(k), Data(k.rawValue.utf8), k.rawValue)
        }
        // Shared items stay where the widget reads them.
        XCTAssertEqual(kc.items[key(.schoolEcykt, group)], Data("school.ecykt".utf8))
        XCTAssertEqual(kc.items[key(.sharedSnapshot, group)], Data("shared.snapshot".utf8))
        XCTAssertNil(kc.items[key(.schoolEcykt, app)])
        // Nothing left: a second run touches nothing.
        kc.calls = []
        XCTAssertEqual(store.migrateItemGroups(), [])
        XCTAssertFalse(kc.calls.contains { $0.hasPrefix("add") || $0.hasPrefix("delete") })
    }

    /// Every item, pinned: the group the widget can read and the accessibility. A change here
    /// changes what the widget can see or when an item can be read; update docs/privacy.md too.
    func testEveryItemsGroupAndAccessibilityArePinned() throws {
        let shared: Set<StoreKey> = [.schoolPortal, .schoolEcykt, .schoolProfile, .schoolPassword, .schoolDevice,
                                     .sharedSnapshot, .sharedReminderLines, .sharedRefreshLease, .sharedCredentialLog, .sharedResetMarker]
        let kc = appKeychain()
        let store = appStore(kc)
        for k in StoreKey.allCases {
            try store.write(Data(k.rawValue.utf8), for: k)
            let home = shared.contains(k) ? group : app, other = shared.contains(k) ? app : group
            XCTAssertEqual(kc.items[key(k, home)], Data(k.rawValue.utf8), k.rawValue)
            XCTAssertNil(kc.items[key(k, other)], k.rawValue)
            XCTAssertEqual(kc.accessibility[key(k, home)], .afterFirstUnlockThisDeviceOnly, k.rawValue)
        }
    }

    /// Builds before the widget refreshed by itself kept the portal token (WhenUnlocked) and the
    /// login device id in the private group: they move to the shared group with the new
    /// accessibility, and the widget then reads them.
    func testPortalTokenAndDeviceMoveIntoTheSharedGroup() throws {
        let kc = appKeychain()
        let portal = key(.schoolPortal, app), device = key(.schoolDevice, app)
        kc.items[portal] = Data("portal".utf8); kc.accessibility[portal] = .whenUnlockedThisDeviceOnly
        kc.items[device] = Data("device".utf8)
        let store = appStore(kc)
        XCTAssertEqual(store.migrateItemGroups(), [])
        XCTAssertNil(kc.items[portal]); XCTAssertNil(kc.items[device])
        XCTAssertEqual(kc.items[key(.schoolPortal, group)], Data("portal".utf8))
        XCTAssertEqual(kc.accessibility[key(.schoolPortal, group)], .afterFirstUnlockThisDeviceOnly)
        XCTAssertEqual(kc.items[key(.schoolDevice, group)], Data("device".utf8))
        let widget = KeychainSecureStore(backend: FakeKeychainView(kc, entitlements: [group]), accessGroup: group)
        XCTAssertEqual(try widget.read(.schoolPortal), Data("portal".utf8))
    }

    /// The move into the shared group keeps the old copy when a step fails (a locked phone can't
    /// read a WhenUnlocked item), so the user stays signed in; the next launch finishes it.
    func testPortalTokenMoveFailureKeepsTheOldCopy() throws {
        let kc = appKeychain()
        let portal = key(.schoolPortal, app)
        kc.items[portal] = Data("portal".utf8)
        kc.failing["copy \(app)"] = -25308
        let store = appStore(kc)
        // The private group can't be read: every shared key may still have a copy there, so all are pending.
        XCTAssertEqual(store.migrateItemGroups(), StoreKey.allCases.filter(\.isShared))
        XCTAssertEqual(kc.items[portal], Data("portal".utf8))
        XCTAssertNil(kc.items[key(.schoolPortal, group)])
        kc.failing = ["add \(group)": -25308]
        XCTAssertEqual(store.migrateItemGroups(), [.schoolPortal])
        XCTAssertEqual(kc.items[portal], Data("portal".utf8))
        kc.failing = [:]
        XCTAssertEqual(store.migrateItemGroups(), [])
        XCTAssertNil(kc.items[portal])
        XCTAssertEqual(try store.read(.schoolPortal), Data("portal".utf8))
    }

    /// The widget has no private group: it never tries to move anything.
    func testWidgetNeverMoves() throws {
        let kc = appKeychain()
        kc.items[key(.schoolPortal, app)] = Data("portal".utf8)
        let widget = KeychainSecureStore(backend: FakeKeychainView(kc, entitlements: [group]), accessGroup: group)
        XCTAssertEqual(widget.migrateItemGroups(), [])
        XCTAssertNil(try widget.read(.schoolPortal))
        XCTAssertEqual(kc.items[key(.schoolPortal, app)], Data("portal".utf8))
    }

    /// A read finds the old copy and moves it on the way.
    func testReadMovesAnOldSharedCopy() throws {
        let kc = appKeychain()
        let binding = Data("binding".utf8)
        kc.items[key(.showerBinding, group)] = binding
        let store = appStore(kc)
        XCTAssertEqual(try store.read(.showerBinding), binding)
        XCTAssertEqual(kc.items[key(.showerBinding, app)], binding)
        XCTAssertNil(kc.items[key(.showerBinding, group)])
    }

    /// Any failed step keeps the shared copy, so the user stays signed in and bound; the next
    /// launch finishes the move.
    func testMigrationFailureKeepsTheOriginalAndRetries() throws {
        let binding = Data("binding".utf8), account = Data("account".utf8)
        // Write to the private group fails.
        do {
            let kc = appKeychain()
            kc.items[key(.showerBinding, group)] = binding
            kc.failing["add \(app)"] = -25308
            let store = appStore(kc)
            XCTAssertEqual(store.migrateItemGroups(), [.showerBinding])
            XCTAssertEqual(kc.items[key(.showerBinding, group)], binding)
            XCTAssertNil(kc.items[key(.showerBinding, app)])
            XCTAssertEqual(try store.read(.showerBinding), binding)
            kc.failing = [:]
            XCTAssertEqual(store.migrateItemGroups(), [])
            XCTAssertEqual(kc.items[key(.showerBinding, app)], binding)
            XCTAssertNil(kc.items[key(.showerBinding, group)])
        }
        // Read-back fails: the shared copy is kept and nothing is deleted from the private group
        // (it may hold a newer value by then); the next run finishes the move.
        do {
            let kc = appKeychain()
            kc.items[key(.laundryAccount, group)] = account
            let store = appStore(kc)
            kc.afterCall = { [unowned kc] call in if call == "add \(FakeKeychain.app)" { kc.failing["copy \(FakeKeychain.app)"] = -25308 } }
            // Once the private group can't be read, the shared keys' old copies are unknown too: pending.
            XCTAssertEqual(store.migrateItemGroups().filter { !$0.isShared }, [.laundryAccount])
            XCTAssertEqual(kc.items[key(.laundryAccount, group)], account)
            XCTAssertFalse(kc.calls.contains("delete \(FakeKeychain.app)"))
            kc.afterCall = nil
            kc.failing = [:]
            XCTAssertEqual(store.migrateItemGroups(), [])
            XCTAssertEqual(try store.read(.laundryAccount), account)
        }
        // Delete of the shared copy fails mid-way: both copies remain, the private one is read,
        // and the next run deletes the leftover without touching the private copy.
        do {
            let kc = appKeychain()
            kc.items[key(.showerSession, group)] = binding
            kc.failing["delete \(group)"] = -25308
            let store = appStore(kc)
            XCTAssertEqual(store.migrateItemGroups(), [.showerSession])
            XCTAssertEqual(kc.items[key(.showerSession, group)], binding)
            XCTAssertEqual(kc.items[key(.showerSession, app)], binding)
            try store.write(Data("newer".utf8), for: .showerSession)
            XCTAssertEqual(try store.read(.showerSession), Data("newer".utf8))
            kc.failing = [:]
            XCTAssertEqual(store.migrateItemGroups(), [])
            XCTAssertNil(kc.items[key(.showerSession, group)])
            XCTAssertEqual(kc.items[key(.showerSession, app)], Data("newer".utf8))
        }
    }

    /// A value written while the move was reading back is never deleted by the move.
    func testMoveNeverDeletesANewerPrivateValue() throws {
        let kc = appKeychain()
        kc.items[key(.laundryAccount, group)] = Data("old".utf8)
        let store = appStore(kc)
        let newer = key(.laundryAccount, app)
        kc.afterCall = { [unowned kc] call in
            if call == "add \(FakeKeychain.app)" { kc.items[newer] = Data("newer".utf8) }
        }
        XCTAssertEqual(store.migrateItemGroups(), [.laundryAccount])
        kc.afterCall = nil
        XCTAssertEqual(kc.items[key(.laundryAccount, app)], Data("newer".utf8))
        XCTAssertEqual(try store.read(.laundryAccount), Data("newer".utf8))
    }

    /// Only a missing entitlement turns a group off; a locked device (or any other failure)
    /// fails this write and the next write tries the group again.
    func testOtherWriteFailuresThrowAndKeepTheGroup() throws {
        let kc = appKeychain()
        let store = appStore(kc)
        kc.failing["add \(app)"] = -25308
        XCTAssertThrowsError(try store.write(Data("x".utf8), for: .showerBinding)) {
            XCTAssertEqual(($0 as? StorageError)?.status, -25308)
        }
        XCTAssertFalse(kc.calls.contains("add -"), "no write outside the private group")
        kc.failing = [:]
        try store.write(Data("y".utf8), for: .showerBinding)
        XCTAssertEqual(kc.items[key(.showerBinding, app)], Data("y".utf8))
        kc.failing["add \(group)"] = -25308
        XCTAssertThrowsError(try store.write(Data("s".utf8), for: .sharedSnapshot))
        XCTAssertFalse(store.isUsingFallback)
        kc.failing = [:]
        try store.write(Data("s".utf8), for: .sharedSnapshot)
        XCTAssertEqual(kc.items[key(.sharedSnapshot, group)], Data("s".utf8))
    }

    /// A probe that fails (before the first unlock) is not remembered: the next use probes
    /// again, and once it answers the store writes shared items where the widget reads them.
    func testFailedGroupProbeIsRetried() throws {
        let answers = ProbeScript([nil, app])
        let probe = KeychainGroupProbe { answers.next() }
        XCTAssertNil(probe.defaultGroup)
        XCTAssertEqual(probe.sharedGroup, group)
        XCTAssertEqual(probe.privateGroup, app)
        XCTAssertEqual(answers.calls, 2)
        _ = probe.defaultGroup
        XCTAssertEqual(answers.calls, 2, "a found group is kept")

        let kc = appKeychain()
        let late = ProbeScript([nil, app])
        let store = KeychainSecureStore(backend: kc, groups: KeychainGroupProbe { late.next() })
        XCTAssertNil(try store.read(.sharedSnapshot))
        try store.write(Data("s".utf8), for: .sharedSnapshot)
        XCTAssertEqual(kc.items[key(.sharedSnapshot, group)], Data("s".utf8))
    }

    /// Sign-out and unbinding remove every copy, old or new.
    func testDeleteRemovesBothCopies() throws {
        let kc = appKeychain()
        kc.items[key(.showerBinding, group)] = Data("old".utf8)
        kc.items[key(.showerBinding, app)] = Data("new".utf8)
        try appStore(kc).delete(.showerBinding)
        XCTAssertTrue(kc.items.isEmpty)
    }

    /// The group the store uses is the one both entitlements files list; the app lists its
    /// private group first so writes without a group never land where the widget reads.
    func testAccessGroupMatchesBothEntitlements() throws {
        XCTAssertEqual(SharedKeychain.groupIdentifier, "com.beamjason.xiaorichang.shared")
        XCTAssertEqual(SharedKeychain.privateGroupIdentifier, "com.beamjason.xiaorichang")
        XCTAssertEqual(SharedKeychain.accessGroup(teamPrefixedFrom: "TEAMID1234.com.beamjason.xiaorichang"), group)
        XCTAssertEqual(SharedKeychain.accessGroup(teamPrefixedFrom: "TEAMID1234.com.beamjason.xiaorichang.shared"), group)
        XCTAssertNil(SharedKeychain.accessGroup(teamPrefixedFrom: "nodot"))
        XCTAssertNil(SharedKeychain.accessGroup(teamPrefixedFrom: ".leadingdot"))
        XCTAssertEqual(SharedKeychain.privateGroup(defaultGroup: app), app)
        XCTAssertNil(SharedKeychain.privateGroup(defaultGroup: group), "the widget has no private group")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func groups(_ path: String) throws -> [String] {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], path)
            return try XCTUnwrap(plist["keychain-access-groups"] as? [String], path)
        }
        XCTAssertEqual(try groups("App/Resources/App.entitlements"),
                       ["$(AppIdentifierPrefix)" + SharedKeychain.privateGroupIdentifier,
                        "$(AppIdentifierPrefix)" + SharedKeychain.groupIdentifier])
        XCTAssertEqual(try groups("Widget/Widget.entitlements"), ["$(AppIdentifierPrefix)" + SharedKeychain.groupIdentifier])
    }

    func testReadErrorsThrow() {
        let kc = FakeKeychain()
        kc.readStatus = -25308 // errSecInteractionNotAllowed (locked device)
        let store = KeychainSecureStore(backend: kc, accessGroup: nil)
        XCTAssertThrowsError(try store.read(.schoolEcykt)) { XCTAssertEqual(($0 as? StorageError)?.status, -25308) }
    }
}

final class SchoolStoresTests: XCTestCase {
    func testVaultRoundTrip() throws {
        let vault = StoredSchoolVault(store: InMemorySecureStore())
        XCTAssertNil(try vault.ecyktSession())
        let s = EcyktSession(token: "t", syscustid: "s", custid: "c", cardUnionID: "u")
        try vault.saveEcyktSession(s)
        XCTAssertEqual(try vault.ecyktSession(), s)
        try vault.savePortalToken(PortalToken("p"))
        XCTAssertEqual(try vault.portalToken(), PortalToken("p"))
        let profile = SchoolProfile(residence: PortalResidence(raw: "示例校区99栋9号1层991房"),
                                    meter: MeterBinding(nodeID: "n", comAddress: "a", label: "99栋 991", nodeIsRoom: true))
        try vault.saveProfile(profile)
        XCTAssertEqual(try vault.profile(), profile)
        try vault.saveEcyktSession(nil)
        XCTAssertNil(try vault.ecyktSession())
        XCTAssertFalse("\(s)".contains("\"t\""))
        XCTAssertFalse(String(describing: PortalToken("secret-portal")).contains("secret-portal"))
    }

    func testWriteFailuresSurface() {
        let mem = InMemorySecureStore()
        mem.failWrites(to: .schoolEcykt)
        let vault = StoredSchoolVault(store: mem)
        XCTAssertThrowsError(try vault.saveEcyktSession(EcyktSession(token: "t", syscustid: "s")))
    }

    func testSnapshotStoreNotifiesAndCapsSize() throws {
        let counter = Counter()
        let store = SharedSnapshotStore(store: InMemorySecureStore(), didWrite: { counter.bump() })
        var snap = HomeSnapshot.empty
        snap.card.succeed(Money(fen: 790), at: Date(timeIntervalSince1970: 100))
        try store.saveSnapshot(snap)
        XCTAssertEqual(try store.loadSnapshot()?.card.value, Money(fen: 790))
        XCTAssertEqual(counter.value, 1)
        snap.roomLabel = String(repeating: "x", count: HomeSnapshot.maxEncodedBytes)
        XCTAssertThrowsError(try store.saveSnapshot(snap))
        XCTAssertEqual(counter.value, 1)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

/// Scripted probe answers (nil = probe failed).
final class ProbeScript: Sendable {
    private let state: OSAllocatedUnfairLock<(answers: [String?], calls: Int)>
    init(_ answers: [String?]) { state = OSAllocatedUnfairLock(initialState: (answers, 0)) }
    var calls: Int { state.withLock { $0.calls } }
    func next() -> String? {
        state.withLock {
            $0.calls += 1
            return $0.answers.count > 1 ? $0.answers.removeFirst() : $0.answers.first ?? nil
        }
    }
}
