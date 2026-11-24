//
//  PortalTokenLockTimeoutTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
import os
@testable import Core
import CoreTestSupport

/// The school accepted the saved password, and the lease file's lock is held elsewhere when the
/// new portal token is to be written (the widget stuck inside a step). The write is tried once
/// more after a short pause; still held, it is logged as a lock timeout and nothing is written.
/// A lost lease is told apart: nothing written as before, and nothing logged as a timeout.
final class PortalTokenLockTimeoutTests: XCTestCase {
    static let savedAccount = SchoolAccount(account: "99100991", password: "synthetic-pw-991")
    static let lockWait: TimeInterval = 0.3

    final class HeldLock: @unchecked Sendable {
        private let holder = OSAllocatedUnfairLock<LeaseWaitBudgetTests.Holder?>(initialState: nil)
        func take(_ url: URL) { holder.withLock { $0 = try? LeaseWaitBudgetTests.Holder(url) } }
        func free() { holder.withLock { $0?.unlock(); $0 = nil } }
    }

    func harness(_ login: FakePasswordLogin, log: RecordingDebugLog) throws -> Harness {
        var h = Harness()
        h.passwordLogin = login
        h.debugLog = log
        try h.signedIn()
        try h.vault.saveAccount(Self.savedAccount)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        return h
    }

    func app(_ h: Harness) -> SnapshotRefresher {
        let file = LeaseFile(url: h.store.leaseFile.url, insideLock: nil, lockWait: Self.lockWait)
        return SnapshotRefresher(school: h.session(), store: h.snapshots,
                                 lease: RefreshLease(file: file, owner: "app-1", now: h.clock.function),
                                 leaseWait: 3, sleep: { _ in try? await Task.sleep(nanoseconds: 1_000_000) },
                                 renewInterval: 3600)
    }

    func timeouts(_ log: RecordingDebugLog) -> [DebugLeaseLockTimeout] {
        log.events.compactMap { if case .leaseLockTimeout(let t) = $0 { return t }; return nil }
    }

    func testALockHeldThroughTheRetryLogsATimeoutAndWritesNothing() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let log = RecordingDebugLog()
        let h = try harness(login, log: log)
        let held = HeldLock(), url = h.store.leaseFile.url
        defer { held.free() }
        login.whileSent { held.take(url) }

        let started = Date()
        let report = await app(h).refresh(inBackground: false)

        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 2 * Self.lockWait + LeaseOwnership.lockRetryPause - 0.05,
                                    "two lock waits and the pause: tried once more")
        XCTAssertEqual(report.outcome, .leaseLost, "as a lost lease")
        XCTAssertNil(try h.vault.portalToken(), "never written without the lock")
        XCTAssertNotNil(try h.vault.account()?.unansweredAt, "the hold stays: the password is not sent again")
        XCTAssertEqual(timeouts(log), [DebugLeaseLockTimeout(.portalToken, role: .app)])
        XCTAssertEqual(login.calls.count, 1)
    }

    func testALockFreedBeforeTheRetryWritesTheToken() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let log = RecordingDebugLog()
        let h = try harness(login, log: log)
        let held = HeldLock(), url = h.store.leaseFile.url
        defer { held.free() }
        login.whileSent {
            held.take(url)
            // Free after the first wait ran out, before the retry.
            Task.detached { try? await Task.sleep(for: .milliseconds(600)); held.free() }
        }

        _ = await app(h).refresh(inBackground: false)

        XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value, "written on the retry")
        XCTAssertEqual(timeouts(log), [])
    }

    func testALostLeaseIsNotLoggedAsATimeout() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let log = RecordingDebugLog()
        let h = try harness(login, log: log)
        let harness = h
        login.whileSent { LoginLostLeaseTests.widgetTakesOver(harness) }

        let started = Date()
        let report = await app(h).refresh(inBackground: false)

        XCTAssertEqual(report.outcome, .leaseLost)
        XCTAssertEqual(try h.vault.portalToken()?.value, LoginLostLeaseTests.widgetToken.value, "the widget's token stays")
        XCTAssertEqual(timeouts(log), [], "a lost lease is not a lock timeout")
        XCTAssertLessThan(Date().timeIntervalSince(started), LeaseOwnership.lockRetryPause, "and is not tried again")
    }
}
