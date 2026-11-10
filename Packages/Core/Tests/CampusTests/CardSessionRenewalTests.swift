import XCTest
@testable import Core
import CoreTestSupport

/// Recharge and the hot-water hand-off on an expired card session: renewed once as home renews
/// it (the forced refresh), then tried once more, before the user is asked to sign in.
final class CardSessionRenewalTests: XCTestCase {
    /// The app's wiring: the step under the lease, the refresh as the renewal.
    func renewingOnce<V: Sendable>(_ h: Harness, _ step: @escaping @Sendable (SchoolSession, LeaseOwnership) async throws -> V) async throws -> V {
        let session = h.session()
        let refresher = SnapshotRefresher(school: session, store: h.snapshots)
        return try await CardSessionRenewal.renewingOnce({
            try await refresher.holdingLease { owning in try await step(session, owning) }
        }, renew: { await refresher.refresh(inBackground: false, includingChanges: true).outcome == .ok })
    }

    /// The stored card session is dead (the first check and the refresh's own), the portal token
    /// mints a new one, and that one is alive.
    func expiredThenRenewedByThePortal(_ h: Harness) throws {
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 2)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "REEXCHANGED-TOKEN"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/card-getRecordList-ok")
    }

    func testAnExpiredRechargeIsRenewedOnceAndOpens() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try expiredThenRenewedByThePortal(h)
        try h.server.serve("ecykt/loginBySysId-mintSeries1")
        let web = try await renewingOnce(h) { session, owning in try await session.rechargeSession(.card, owning: owning) }
        XCTAssertEqual(try JSONValue.parse(web.stateJSON)["logintoken"]?.text, "REDACTED_TOKEN_9")
        XCTAssertEqual(h.server.requests(path: "/csalogintoken/450010").count, 1, "one renewal")
        XCTAssertEqual(h.loginBySysIdCalls(), 1, "only the second try mints the recharge token")
        XCTAssertEqual(h.server.requests(path: "/loginBySysId").first?.bodyField("acc_token"), "REEXCHANGED-TOKEN")
        XCTAssertEqual(h.livenessCalls(), 4, "expired twice, then the renewed session and the second try")
    }

    func testAnExpiredHandOffIsRenewedOnceAndGoesOn() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try expiredThenRenewedByThePortal(h)
        try h.server.serve("ecykt/getSignData-ok")
        let handoff = try await renewingOnce(h) { session, owning in try await session.showerHandoff(owning: owning) }
        XCTAssertEqual(handoff.userId, "90001")
        XCTAssertEqual(h.server.requests(path: "/getSignData").count, 1)
        XCTAssertEqual(h.server.requests(path: "/getSignData").first?.bodyField("acc_token"), "REEXCHANGED-TOKEN")
        XCTAssertEqual(h.server.requests(path: "/csalogintoken/450010").count, 1)
    }

    /// Nothing to renew with (no portal token, no saved password): the expiry reaches the user
    /// after one try and one renewal attempt; nothing is minted.
    func testWithNothingToRenewWithTheUserIsAskedToSignIn() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        try h.server.serve("ecykt/loginBySysId-mintSeries1")
        await T.expectError(.sessionExpired(.ecykt)) {
            _ = try await self.renewingOnce(h) { session, owning in try await session.rechargeSession(.card, owning: owning) }
        }
        XCTAssertEqual(h.livenessCalls(), 2, "the recharge check and the refresh's own")
        XCTAssertEqual(h.loginBySysIdCalls(), 0)
    }

    /// Renewed, and the step still finds the session expired: asked once more, never in a loop.
    func testTheStepIsTriedTwiceAtMost() async {
        var attempts = 0, renewals = 0
        do {
            _ = try await CardSessionRenewal.renewingOnce({ () async throws -> Int in
                attempts += 1
                throw ServiceError.sessionExpired(.ecykt)
            }, renew: { renewals += 1; return true })
            XCTFail("expected the expiry")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(renewals, 1)
    }

    /// Only an expiry is renewed: no network, a refusal or a busy lease go to the user as they are.
    func testOtherFailuresAreNotRenewed() async {
        let failures: [Error] = [ServiceError.offline, ServiceError.rejected(.ecykt, code: "noCard", message: "这个账号还没有绑定校园卡"),
                                 SchoolLoginFailure.busy]
        for failure in failures {
            var attempts = 0, renewals = 0
            do {
                _ = try await CardSessionRenewal.renewingOnce({ () async throws -> Int in
                    attempts += 1
                    throw failure
                }, renew: { renewals += 1; return true })
                XCTFail("expected \(failure)")
            } catch {}
            XCTAssertEqual(attempts, 1, "\(failure)")
            XCTAssertEqual(renewals, 0, "\(failure)")
        }
    }

    /// A renewal that did not read the card: the first expiry is what the user sees.
    func testAFailedRenewalIsNotFollowedByASecondTry() async {
        var attempts = 0
        do {
            _ = try await CardSessionRenewal.renewingOnce({ () async throws -> Int in
                attempts += 1
                throw ServiceError.sessionExpired(.ecykt)
            }, renew: { false })
            XCTFail("expected the expiry")
        } catch {
            XCTAssertEqual(error as? ServiceError, .sessionExpired(.ecykt))
        }
        XCTAssertEqual(attempts, 1)
    }
}
