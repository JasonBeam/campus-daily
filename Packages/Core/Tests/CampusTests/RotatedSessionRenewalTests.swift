import XCTest
import os
@testable import Core
import CoreTestSupport

/// The other process stored a new card session while this one found the old one dead.
final class RotatedSessionRenewalTests: XCTestCase {
    static let livenessURL = "https://ecykt.gdbtu.edu.cn/ykt-mini/api/customer/getSysBindCustInfo"

    /// The other process renewed the session while this one read, and that one is dead too:
    /// this read renews it, and its fresh session is kept (it is written over the one found).
    func testRenewingOverASessionTheOtherProcessStoredKeepsTheFreshOne() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 2)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "RENEWED"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let vault = h.vault
        let once = OSAllocatedUnfairLock(initialState: false)
        let reading = await h.session().refresh(inBackground: false, mayMint: {
            if once.withLock({ let first = !$0; $0 = true; return first }) {
                try? vault.saveEcyktSession(T.session(token: "OTHER-PROCESS"))
            }
            return true
        }, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .ok)
        XCTAssertEqual(h.server.requests(path: "/getSysBindCustInfo").map { $0.header("acc_token") },
                       ["REDACTED_TOKEN_2", "OTHER-PROCESS", "RENEWED"])
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "RENEWED")
    }

    /// The other process's session can't be checked (no network): nothing is minted on a guess.
    func testASessionTheOtherProcessStoredThatCantBeCheckedIsAFailedRead() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.fail("POST", Self.livenessURL, with: .notConnectedToInternet)
        let vault = h.vault
        let reading = await h.session().refresh(inBackground: false, mayMint: {
            try? vault.saveEcyktSession(T.session(token: "OTHER-PROCESS"))
            return true
        }, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .failed(.offline))
        XCTAssertTrue(h.server.requests(path: "/getMyECard").isEmpty)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "OTHER-PROCESS")
    }
}
