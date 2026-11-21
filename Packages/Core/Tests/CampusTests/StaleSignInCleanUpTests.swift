//
//  StaleSignInCleanUpTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core
import CoreTestSupport

/// A password sign-in still waiting for the school when 退出登录 and a new sign-in of the same
/// account overtake it: its late failure was caused by them, not by writes of its own. It asks
/// for no clean-up and changes nobody, so the new sign-in's account stays as it is.
final class StaleSignInCleanUpTests: XCTestCase {
    /// The first login is held until `release()`; later ones answer at once.
    final class HeldLogin: SchoolPasswordLogin, @unchecked Sendable {
        // @unchecked: every var is touched only under `lock`.
        private let lock = NSLock()
        private var calls = 0
        private var released = false
        private var waiting: CheckedContinuation<Void, Never>?
        let reached: XCTestExpectation

        init(_ test: XCTestCase) { reached = test.expectation(description: "first login sent") }

        func login(account: String, password: String, visitorID: String) async throws -> PortalToken {
            let first = lock.withLock { () -> Bool in defer { calls += 1 }; return calls == 0 }
            if first {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    let go = lock.withLock { () -> Bool in
                        if released { return true }
                        waiting = c; return false
                    }
                    reached.fulfill()
                    if go { c.resume() }
                }
            }
            return SchoolPasswordSignInTests.freshToken
        }

        func release() {
            let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                released = true; defer { waiting = nil }; return waiting
            }
            c?.resume()
        }
    }

    /// What one sign-in asked of its caller.
    @MainActor final class Asked {
        var changes = 0
        var cleanUps: [Bool] = []
    }

    @MainActor static func signIn(_ session: SchoolSession, _ asked: Asked) async throws -> SignInSummary {
        try await SchoolSession.signingIn(on: session, {
            try await session.signIn(account: "99100991", password: "synthetic-pw-991", savePassword: false, owning: .unchecked)
        }, changed: { asked.changes += 1 }, cleanUp: { unconfirmed, _ in asked.cleanUps.append(unconfirmed) })
    }

    @MainActor func testAnOvertakenSignInThatFailsAsksForNoCleanUp() async throws {
        let login = HeldLogin(self)
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991"))
        try h.server.serve("portal/getMyInfo-ok")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "PW-TOKEN"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let session = h.session()
        let first = Asked(), second = Asked()

        let attempt = Task { @MainActor in try await Self.signIn(session, first) }
        await fulfillment(of: [login.reached], timeout: 5)
        try await session.signOut()
        _ = try await Self.signIn(session, second)
        XCTAssertEqual(second.changes, 1, "signed in after the sign-out")

        login.release()
        do {
            _ = try await attempt.value
            XCTFail("the first sign-in was overtaken")
        } catch {}

        XCTAssertEqual(first.cleanUps, [], "nothing of the first sign-in was written")
        XCTAssertEqual(first.changes, 0)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "PW-TOKEN")
        XCTAssertEqual(try h.vault.account()?.account, "99100991")
    }
}
