import XCTest
@testable import Core

/// Before the first unlock the Keychain can't be read: that is "unknown", not "signed out".
final class WidgetStoredDataTests: XCTestCase {
    func testUnreadableKeychainIsNotSignedOut() throws {
        let store = InMemorySecureStore()
        let snapshots = SharedSnapshotStore(store: store)
        let vault = StoredSchoolVault(store: store)
        let signedIn = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: Date(timeIntervalSince1970: 1_793_300_000)))
        try snapshots.saveSnapshot(signedIn)
        try vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        XCTAssertEqual(WidgetStoredData.read(snapshots: snapshots, vault: vault),
                       WidgetStoredData(snapshot: signedIn, account: SchoolAccount(account: "99100991", password: "synthetic-pw-991")))
        store.failReads()
        XCTAssertNil(WidgetStoredData.read(snapshots: snapshots, vault: vault), "unreadable, not empty")
        store.failReads(false)
        XCTAssertNotNil(WidgetStoredData.read(snapshots: snapshots, vault: vault))
    }

    func testNothingStoredIsReadableAndEmpty() {
        let store = InMemorySecureStore()
        XCTAssertEqual(WidgetStoredData.read(snapshots: SharedSnapshotStore(store: store), vault: StoredSchoolVault(store: store)),
                       WidgetStoredData(snapshot: nil, account: nil))
    }

    /// A damaged item can't keep the widget waiting forever: it counts as absent.
    func testAnUndecodableItemCountsAsAbsent() throws {
        let store = InMemorySecureStore()
        try store.write(Data("not json".utf8), for: .sharedSnapshot)
        let read = WidgetStoredData.read(snapshots: SharedSnapshotStore(store: store), vault: StoredSchoolVault(store: store))
        XCTAssertEqual(read, WidgetStoredData(snapshot: nil, account: nil))
    }

    func testRetryIsSoon() {
        XCTAssertLessThanOrEqual(WidgetStoredData.unreadableRetry, 5 * 60)
    }
}
