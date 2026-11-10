import XCTest
@testable import Core
import CoreTestSupport

/// A build signed without the App Group (re-signed under another group) has no shared lease
/// file. The app then keeps its lease in its own container, so its reads, logins, recharge and
/// hand-off still take turns inside the app instead of reporting "busy" forever or running side
/// by side; the widget has no lease file at all and leaves every school read to the app, so the
/// two never read at once.
final class NoAppGroupTests: XCTestCase {
    /// The app's own container (Application Support), not created yet.
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("own-container-\(UUID().uuidString)", isDirectory: true)

    override func tearDown() {
        try? FileManager.default.removeItem(at: container)
        super.tearDown()
    }

    /// Built the way the app and the widget build theirs when no App Group is available.
    func stack(_ h: Harness, role: String, leaseWait: TimeInterval = 5) -> SchoolRefreshStack {
        let file = role == "widget" ? RefreshLease.sharedFile(appGroup: nil)
            : RefreshLease.appFile(appGroup: nil, ownContainer: container)
        return SchoolRefreshStack(store: h.store, http: h.server.makeClient(), role: role, leaseWait: leaseWait,
                                  leaseFile: file, diagnostic: { _ in })
    }

    func testAppKeepsItsLeaseInItsOwnContainer() throws {
        XCTAssertNil(RefreshLease.sharedFile(appGroup: nil))
        let file = try XCTUnwrap(RefreshLease.appFile(appGroup: nil, ownContainer: container))
        XCTAssertEqual(file.url.standardizedFileURL, container.appendingPathComponent("refresh.lease").standardizedFileURL)
        XCTAssertTrue(RefreshLease(file: file, owner: "app-1").acquire(), "the folder is created for it")
        XCTAssertFalse(RefreshLease(file: file, owner: "app-2").acquire())
    }

    /// The lease file in the app's own container is not backed up: a restore must not bring
    /// back a lease, and it holds nothing worth keeping.
    func testTheOwnLeaseFileIsNotBackedUp() throws {
        let file = try XCTUnwrap(RefreshLease.appFile(appGroup: nil, ownContainer: container))
        let values = try file.url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        XCTAssertEqual(try RefreshLease.appFile(appGroup: nil, ownContainer: container)?.url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
                       true, "found again on the next launch")
    }

    func testAppSignsInUnderItsOwnLease() async throws {
        let value = try await stack(Harness(), role: "app").refresher.holdingLease { owning in try owning.write { 7 } }
        XCTAssertEqual(value, 7)
    }

    func testAppReadsUnderItsOwnLease() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/card-getRecordList-ok")
        let report = await stack(h, role: "app").refresher.refresh(inBackground: false)
        XCTAssertFalse(report.leaseBusy)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 790))
        XCTAssertTrue(report.snapshotSaved)
    }

    /// Two logins in the app (the form's and Settings', or a login beside recharge) run one
    /// after the other, never side by side.
    func testTwoLoginsInTheAppTakeTurns() async throws {
        let refresher = stack(Harness(), role: "app").refresher
        let probe = OverlapProbe()
        async let first: Void = refresher.holdingLease { _ in
            await probe.enter(); try await Task.sleep(nanoseconds: 300_000_000); await probe.leave()
        }
        async let second: Void = refresher.holdingLease { _ in
            await probe.enter(); try await Task.sleep(nanoseconds: 300_000_000); await probe.leave()
        }
        _ = try await (first, second)
        let most = await probe.most
        let runs = await probe.runs
        XCTAssertEqual(runs, 2)
        XCTAssertEqual(most, 1, "the second login waits for the first")
    }

    /// A refresh started while a login in the app holds the lease waits for it, and gives up
    /// as busy (nothing sent) if the login takes longer than it waits.
    func testRefreshWaitsForALoginInTheApp() async throws {
        let h = Harness()
        try h.signedIn()
        let refresher = stack(h, role: "app", leaseWait: 1).refresher
        let report = try await refresher.holdingLease { _ in await refresher.refresh(inBackground: true) }
        XCTAssertTrue(report.leaseBusy)
        XCTAssertTrue(h.server.requests.isEmpty, "nothing is sent beside the login")
    }

    func testWidgetLeavesTheReadToTheApp() async throws {
        let h = Harness()
        try h.signedIn()
        let report = await stack(h, role: "widget").refresher.refresh(inBackground: true)
        XCTAssertTrue(report.leaseBusy)
        XCTAssertTrue(h.server.requests.isEmpty, "nothing is sent")
    }

    /// The widget never takes the app's own lease file: even while the app holds nothing, it
    /// does not read.
    func testWidgetDoesNotReadBesideTheAppsOwnLease() async throws {
        let h = Harness()
        try h.signedIn()
        let app = stack(h, role: "app")
        let widget = stack(h, role: "widget")
        let report = try await app.refresher.holdingLease { _ in await widget.refresher.refresh(inBackground: true) }
        XCTAssertTrue(report.leaseBusy)
        let alone = await widget.refresher.refresh(inBackground: true)
        XCTAssertTrue(alone.leaseBusy)
        XCTAssertTrue(h.server.requests.isEmpty, "nothing is sent")
    }

    /// A lease without a file can never be taken (the app with no container to keep its own in):
    /// a login under it runs without the lease rather than waiting and failing as busy.
    func testLoginUnderALeaseWithoutAFileRunsWithoutIt() async throws {
        let h = Harness()
        let refresher = SnapshotRefresher(school: h.session(), store: h.snapshots,
                                          lease: RefreshLease(file: nil, owner: "app-1"), leaseWait: 5,
                                          sleep: { _ in XCTFail("nothing to wait for") })
        let value = try await refresher.holdingLease { owning -> Int in
            XCTAssertEqual(try owning.write { 1 }, 1, "writes are not blocked")
            return 2
        }
        XCTAssertEqual(value, 2)
    }
}

/// Counts how many bodies run at once.
private actor OverlapProbe {
    private(set) var most = 0
    private(set) var runs = 0
    private var now = 0
    func enter() { now += 1; runs += 1; most = max(most, now) }
    func leave() { now -= 1 }
}
