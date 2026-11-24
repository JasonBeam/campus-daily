//
//  SignOutRecordsPreferencesTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 退出登录 forgets the records page's span and term start: the next account starts from 7 天 and
/// 3月1日 / 9月1日.
@MainActor
final class SignOutRecordsPreferencesTests: XCTestCase {
    func testSignOutClearsTheSpanAndTheTermStart() async {
        let defaults = SampleDefaults()
        let services = CampusServices(kind:.live, secureStore:ScriptedStore(), defaults:defaults, sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:SampleShowerTransport(), leaseFile:nil,
                                      applicationSupport:nil, sharedDidChange:{})
        let campus = CampusModel(services:services, stack:services.schoolStack(), reminders:.sample(defaults:defaults)) { nil }
        defaults.set("term", forKey:SpendSpan.storeKey)
        defaults.set("20261114", forKey:TermStartStore.key)
        defaults.set("kept", forKey:"another.key")

        campus.signOut()

        XCTAssertNil(defaults.object(forKey:SpendSpan.storeKey))
        XCTAssertNil(defaults.object(forKey:TermStartStore.key))
        XCTAssertEqual(defaults.string(forKey:"another.key"), "kept")
        let next = CardRecordsModel(source:SampleData.recordsSource(delay:.milliseconds(1)), preferences:defaults)
        XCTAssertEqual(next.statsSpan, .week)
        XCTAssertNil(next.customTermStart)
        await campus.signOutsFinished()
    }
}
