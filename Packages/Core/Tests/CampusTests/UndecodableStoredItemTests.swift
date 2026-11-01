import XCTest
@testable import Core
import CoreTestSupport

/// A stored school item that no longer decodes (damaged, or an older shape) must not block the
/// sign-ins that would write over it: they compare what is stored byte for byte, so such an
/// item compares equal to itself and is replaced.
final class UndecodableStoredItemTests: XCTestCase {
    static let damaged = Data(#"{"shape":"older","paused":null}"#.utf8)
    static let keys: [StoreKey] = [.schoolEcykt, .schoolPortal, .schoolPassword]

    func testTheFormSignInReplacesAnItemThatNoLongerDecodes() async throws {
        for key in Self.keys {
            var h = Harness()
            h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
            try h.signedIn(portal: true)
            try h.store.write(Self.damaged, for: key)
            try h.server.serve("portal/getMyInfo-ok")
            h.server.serve(try T.eCardWithTicket())
            h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "PW-TOKEN"))
            try h.server.serve("ecykt/getSysBindCustInfo-ok")
            _ = try await h.session().signIn(account: "99100991", password: "synthetic-pw-991", savePassword: true, owning: .unchecked)
            XCTAssertEqual(try h.vault.ecyktSession()?.token, "PW-TOKEN", "\(key)")
            XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value, "\(key)")
            XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991", password: "synthetic-pw-991"), "\(key)")
        }
    }

    func testTheWebSignInReplacesAnItemThatNoLongerDecodes() async throws {
        for key in Self.keys {
            let h = Harness()
            try h.signedIn(portal: true)
            try h.store.write(Self.damaged, for: key)
            try h.server.serve("ecykt/getSysBindCustInfo-ok")
            let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
            _ = try await h.session().adoptWebState(try state.encoded(), owning: .unchecked)
            XCTAssertNotNil(try h.vault.ecyktSession(), "\(key): the card session is written (readable again)")
        }
    }

    func testSavingAPasswordReplacesAPortalTokenThatNoLongerDecodes() async throws {
        var h = Harness()
        h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991"))
        try h.store.write(Self.damaged, for: .schoolPortal)
        try await h.session().savePassword("synthetic-pw-991", owning: .unchecked)
        XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value)
        XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
    }

    /// Bytes still decide: an item the other process rewrote meanwhile (other bytes, even if
    /// neither decodes) is not written over.
    func testAnItemRewrittenMeanwhileIsStillNotWrittenOver() async throws {
        var h = Harness()
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        h.passwordLogin = login
        try h.signedIn(portal: true)
        try h.store.write(Self.damaged, for: .schoolPortal)
        let other = Data(#"{"shape":"other"}"#.utf8)
        let store = h.store
        login.whileSent { try? store.write(other, for: .schoolPortal) }
        try h.server.serve("portal/getMyInfo-ok")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "PW-TOKEN"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        do {
            _ = try await h.session().signIn(account: "99100991", password: "synthetic-pw-991", savePassword: true, owning: .unchecked)
            XCTFail("written over the other process's item")
        } catch {
            XCTAssertEqual(error as? SchoolLoginFailure, .busy)
        }
        XCTAssertEqual(try h.store.read(.schoolPortal), other)
    }
}
