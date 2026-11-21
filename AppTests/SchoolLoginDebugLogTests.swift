//
//  SchoolLoginDebugLogTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/17.
//

import XCTest
import Core
@testable import XiaoRiChang

/// A failed password login from the form leaves one `school.directLogin` line with its category:
/// never the school's page, the account or the password.
@MainActor
final class SchoolLoginDebugLogTests: XCTestCase {
    /// Every school request answers with a page that has no login form and some text.
    private final class StrangePage: HTTPClient, @unchecked Sendable {
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            HTTPResponse(status:200, headers:["Content-Type":"text/html"], body:Data("<html><body>系统维护中 99100991</body></html>".utf8))
        }
    }

    func testAnUnknownPageIsLoggedAsUnknownOnly() async {
        let log = AppRecordingLog()
        let services = CampusServices(kind:.live, secureStore:InMemorySecureStore(), defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:StrangePage(), showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:SampleShowerTransport(), leaseFile:nil,
                                      applicationSupport:nil, sharedDidChange:{}, debugLog:log)
        let campus = CampusModel(services:services, stack:services.schoolStack(), reminders:.sample(defaults:services.defaults)) { nil }
        let state = await campus.submitLogin(account:"99100991", password:"synthetic-pw-991", savePassword:false)
        XCTAssertEqual(state, .blocked(.unknown))
        let logins = log.events.filter { if case .schoolDirectLogin = $0 { return true }; return false }
        XCTAssertEqual(logins, [.schoolDirectLogin(.unknown)])
        let text = log.events.map { $0.name + " " + $0.fields { _ in "tag" } }.joined(separator:"\n")
        for secret in ["99100991", "synthetic-pw-991", "系统维护中", "html"] {
            XCTAssertFalse(text.contains(secret), "\(secret) in \(text)")
        }
        XCTAssertTrue(text.contains("school.directLogin cause=unknown"), text)
    }
}
