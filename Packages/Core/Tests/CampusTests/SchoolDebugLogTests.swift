//
//  SchoolDebugLogTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/05.
//

import XCTest
import os
@testable import Core
import CoreTestSupport

/// The school's part of the TestFlight log: each refresh's outcome, the portal renewals, the
/// dead credentials' ages and the saved-password logins; never a token, an account or a password.
final class SchoolDebugLogTests: XCTestCase {
    /// "PORTAL" is checked as written only: `service=portal` is the service's name, not the token.
    let secrets = ["MINTED", "PW-TOKEN", "AFTER-MOVE", "99100991", "synthetic-pw-991", "99000000000000000000000000000991"]

    func testARefreshLeavesItsOutcomeTheRenewalAndTheExpiry() async throws {
        let log = RecordingDebugLog()
        var h = Harness()
        h.debugLog = log
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket(), times: 1)
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "MINTED"), times: 1)
        try h.server.serve("ecykt/getSysBindCustInfo-ok", times: 2)
        try h.server.serve("ecykt/getUserBalance-ok")
        let session = h.session()
        let refresher = SnapshotRefresher(school: session, store: h.snapshots)
        _ = await refresher.refresh(inBackground: true)
        XCTAssertEqual(log.events.filter { if case .schoolRenew = $0 { return true }; return false }, [.schoolRenew(.ok)])
        XCTAssertEqual(log.events.last, .schoolRefresh(.ok))
        h.clock.advance(92 * 60)
        _ = await refresher.refresh(inBackground: true)
        h.clock.advance(60 * 60)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"))
        _ = await refresher.refresh(inBackground: true)
        XCTAssertTrue(log.events.contains(.schoolCredentialExpired(kind: .card, ageMinutes: 152, aliveMinutes: 92)),
                      log.lines().joined(separator: "\n"))
        XCTAssertTrue(log.lines().contains("school.credentialExpired kind=card ageMinutes=152 aliveMinutes=92"))
        XCTAssertTrue(log.lines().contains { $0.hasPrefix("school.renew failed kind=sessionExpired service=portal") },
                      log.lines().joined(separator: "\n"))
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: log.lines().joined(separator: "\n")), [])
        XCTAssertFalse(log.lines().joined(separator: "\n").contains("PORTAL"))
    }

    func testAPortalTokenRunOutReadsAsNeedsLogin() async throws {
        let log = RecordingDebugLog()
        var h = Harness()
        h.debugLog = log
        try h.signedIn()
        try h.vault.savePortalToken(PortalToken("PORTAL", obtainedAt: h.clock.now))
        h.clock.advance(481 * 60)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"))
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertTrue(log.events.contains(.schoolCredentialExpired(kind: .portal, ageMinutes: 481, aliveMinutes: nil)))
        XCTAssertEqual(log.events.last, .schoolRefresh(.needsLogin(DebugError(ServiceError.sessionExpired(.portal)))))
        XCTAssertEqual(log.lines().last, "school.refresh needsLogin kind=sessionExpired service=portal")
    }

    func testNotSignedIn() async {
        let log = RecordingDebugLog()
        var h = Harness()
        h.debugLog = log
        _ = await h.session().refresh(inBackground: false, owning: .unchecked)
        XCTAssertEqual(log.events, [.schoolRefresh(.notSignedIn)])
    }

    /// The saved password: deferred in the widget before the id moved, then sent; never its value.
    func testTheSavedPasswordLoginIsLoggedWithoutAnyValue() async throws {
        let log = RecordingDebugLog()
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        h.debugLog = log
        h.createsLoginDeviceID = false
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 2)
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertTrue(log.events.contains(.schoolSavedLogin(.deferred(.noLoginDeviceID))))

        try h.vault.saveLoginDeviceID("99000000000000000000000000000991")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-MOVE"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertTrue(log.events.contains(.schoolSavedLogin(.sent)))
        XCTAssertTrue(log.lines().contains("school.savedLogin sent"), log.lines().joined(separator: "\n"))
        XCTAssertTrue(log.lines().allSatisfy(DebugLogScreen.isSafe), "no line is dropped by the log's screen")
        XCTAssertEqual(log.events.last, .schoolRefresh(.ok))
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: log.lines().joined(separator: "\n")), [])
    }

    /// 退出登录 empties the log and drops its salt.
    func testSigningOutClearsTheLog() async throws {
        let log = RecordingDebugLog()
        let h = Harness()
        try h.signedIn()
        let session = h.session()
        let signOuts = SchoolSignOut(session: session, refresher: SnapshotRefresher(school: session, store: h.snapshots), debugLog: log)
        _ = await signOuts.start().value
        XCTAssertEqual(log.clears, 1)
    }

    // MARK: The meter's readings

    /// Each successful refresh logs the bound meter's numbers once, named by the process that read
    /// it, with the meter only as a salted tag: no address, room, token or card id.
    func testEachMeterReadIsLoggedWithItsRoleAndNoIds() async throws {
        for (background, widget, role) in [(false, false, DebugMeterRead.Role.app), (true, false, .background), (false, true, .widget)] {
            let log = RecordingDebugLog()
            var h = Harness()
            h.debugLog = log
            h.createsLoginDeviceID = !widget
            try h.signedIn(meter: Harness.roomBinding)
            try h.server.serve("ecykt/getSysBindCustInfo-ok")
            try h.server.serve("ecykt/getUserBalance-ok")
            try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
            try h.server.serve("ecykt/card-getRecordList-ok")
            let reading = await h.session().refresh(inBackground: background, owning: .unchecked)
            XCTAssertEqual(reading.outcome, .ok)
            let reads = log.events.compactMap { if case .meterRead(let m) = $0 { return m }; return nil }
            XCTAssertEqual(reads.count, 1, "\(role)")
            let read = try XCTUnwrap(reads.first)
            XCTAssertEqual(read.role, role)
            XCTAssertEqual(read.meter, DebugTag(.meter, "000000000991"))
            XCTAssertEqual(read.reading, Decimal(string: "1234.56"))
            XCTAssertEqual(read.schoolTime?.text, "10-30T08:10:22")
            XCTAssertEqual(read.remainingKWh, Decimal(string: "52.00"))
            XCTAssertEqual(read.leftMoneyFen, 3692)
            XCTAssertEqual(read.price, Decimal(string: "0.71"))
            XCTAssertEqual(read.daysLeft, Decimal(string: "3.2"))
            XCTAssertEqual(log.lines().first { $0.hasPrefix("school.meter") },
                           "school.meter role=\(role.rawValue) meter=e:tag reading=1234.56 at=10-30T08:10:22 kwh=52 fen=3692 price=0.71 days=3.2")
            let ids = secrets + ["000000000991", "991001001000109000001003", "REDACTED_TOKEN_2", T.syscustid, T.custid,
                                 "TESTid00000000000000000000000001", "99栋"]
            XCTAssertEqual(DebugLogTesting.leaks(ids, in: log.lines().joined(separator: "\n")), [])
        }
    }

    /// Through the TestFlight log itself: the meter's address is written as a short salted tag.
    func testTheMeterAddressIsWrittenAsATag() throws {
        let dir = DebugLogTesting.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = FileDebugLog(directory: FileDebugLog.directory(in: dir))
        let meter = Meter(comAddress: "000000000991", name: "99栋991", remainingKWh: Decimal(string: "52.00"),
                          updatedAt: "2026-10-30 08:10:22", meterData: Decimal(string: "1234.5600"))
        log.record(.meterRead(DebugMeterRead(meter, role: .app)))
        log.record(.meterRead(DebugMeterRead(meter, role: .app)))
        log.flush()
        let lines = log.lines()
        XCTAssertEqual(lines.count, 2)
        let line = try XCTUnwrap(lines.first)
        XCTAssertNotNil(line.range(of: #"school\.meter role=app meter=e:[0-9a-f]{6} reading=1234\.56 at=10-30T08:10:22 kwh=52$"#,
                                   options: .regularExpression), line)
        XCTAssertEqual(lines[0].split(separator: " ").last { $0.hasPrefix("meter=") },
                       lines[1].split(separator: " ").last { $0.hasPrefix("meter=") }, "the same meter, the same tag")
        XCTAssertEqual(DebugLogTesting.leaks(["000000000991", "99栋991"], in: lines.joined(separator: "\n")), [])
    }
}
