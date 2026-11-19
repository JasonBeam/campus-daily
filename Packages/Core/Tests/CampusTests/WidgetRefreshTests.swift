import XCTest
@testable import Core
import CoreTestSupport

/// The widget's own read: the same stack as the app (school session + refresher + lease) over
/// the shared store, run before each timeline.
final class WidgetRefreshTests: XCTestCase {
    func stack(_ h: Harness, role: String = "widget", leaseWait: TimeInterval = SchoolRefreshStack.widgetLeaseWait) -> SchoolRefreshStack {
        SchoolRefreshStack(store: h.store, http: h.server.makeClient(), role: role, leaseWait: leaseWait, leaseFile: h.store.leaseFile, diagnostic: { _ in })
    }

    func signedInWithOldSnapshot(_ h: Harness) throws {
        try h.signedIn()
        var old = HomeSnapshot(checkedAt: Date(timeIntervalSinceNow: -3600))
        old.card.succeed(Money(fen: 100), at: Date(timeIntervalSinceNow: -3600))
        try h.snapshots.saveSnapshot(old)
    }

    func testWidgetReadWritesTheSharedSnapshot() async throws {
        let h = Harness()
        try signedInWithOldSnapshot(h)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let drawn = await WidgetRefresh.run(stack(h).refresher, now: Date(), deadline: 10)
        XCTAssertEqual(drawn.card.value, Money(fen: 790))
        XCTAssertEqual(try h.snapshots.loadSnapshot(), drawn, "written through the refresher")
        XCTAssertNil(h.store.leaseFile.storedOwner(), "the lease is given back")
    }

    func testNoReadWhenNobodyIsSignedIn() async throws {
        let h = Harness()
        let drawn = await WidgetRefresh.run(stack(h).refresher, now: Date(), deadline: 10)
        XCTAssertEqual(drawn, .empty)
        XCTAssertTrue(h.server.requests.isEmpty)
    }

    func testNoReadRightAfterTheAppChecked() async throws {
        let h = Harness()
        try h.signedIn()
        let recent = HomeSnapshot(checkedAt: Date(timeIntervalSinceNow: -60))
        try h.snapshots.saveSnapshot(recent)
        let drawn = await WidgetRefresh.run(stack(h).refresher, now: Date(), deadline: 10)
        XCTAssertEqual(drawn, recent)
        XCTAssertTrue(h.server.requests.isEmpty)
    }

    /// While the app holds the lease, the widget draws the stored snapshot and reads nothing.
    func testAppHoldingTheLeaseMeansTheWidgetJustDraws() async throws {
        let h = Harness()
        try signedInWithOldSnapshot(h)
        let stored = try h.snapshots.loadSnapshot()
        XCTAssertTrue(RefreshLease(file: h.store.leaseFile, owner: RefreshLease.owner("app")).acquire())
        let drawn = await WidgetRefresh.run(stack(h, leaseWait: 0).refresher, now: Date(), deadline: 10)
        XCTAssertEqual(drawn, stored)
        XCTAssertTrue(h.server.requests.isEmpty)
    }

    /// A read that outlasts the deadline: the stored snapshot is drawn at once, and the late
    /// read writes nothing.
    func testDeadlineDrawsTheStoredSnapshot() async throws {
        let h = Harness()
        try signedInWithOldSnapshot(h)
        let stored = try h.snapshots.loadSnapshot()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let release = DispatchSemaphore(value: 0)
        h.server.gate { r in if r.url.path.hasSuffix("/getSysBindCustInfo") { release.wait() } }
        let refresher = stack(h).refresher
        let drawn = await WidgetRefresh.run(refresher, now: Date(), deadline: 0.2)
        XCTAssertEqual(drawn, stored)
        release.signal()
        // The cancelled read ends (and gives the lease back) without writing.
        for _ in 0..<200 where h.store.leaseFile.storedOwner() != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(h.store.leaseFile.storedOwner())
        XCTAssertEqual(try h.snapshots.loadSnapshot(), stored)
    }

    func testOnlyTheAppCreatesTheLoginDeviceID() async {
        let h = Harness()
        let widget = await stack(h).session.createsLoginDeviceID
        let app = await stack(h, role: "app").session.createsLoginDeviceID
        XCTAssertFalse(widget)
        XCTAssertTrue(app)
    }

    func testRolesNameTheLeaseOwner() async throws {
        let h = Harness()
        let app = await stack(h, role: "app").refresher.lease?.owner
        let again = await stack(h, role: "app").refresher.lease?.owner
        let widget = await stack(h).refresher.lease?.owner
        XCTAssertTrue(app?.hasPrefix("app-") ?? false)
        XCTAssertTrue(widget?.hasPrefix("widget-") ?? false)
        XCTAssertNotEqual(app, again, "a new id per process")
    }
}
