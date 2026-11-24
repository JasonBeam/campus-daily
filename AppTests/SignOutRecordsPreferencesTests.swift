//
//  SignOutRecordsPreferencesTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 退出登录 and a sign-in as someone else forget the records page's span and term start: the next
/// account starts from 7 天 and 3月1日 / 9月1日. A sign-out that fails keeps them.
@MainActor
final class SignOutRecordsPreferencesTests: XCTestCase {
    private func campus(_ store: ScriptedStore = ScriptedStore(), defaults: SampleDefaults) -> CampusModel {
        let services = CampusServices(kind:.live, secureStore:store, defaults:defaults, sharedPreferences:nil,
                                      schoolHTTP:SampleHTTPClient(), showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:SampleShowerTransport(), leaseFile:nil,
                                      applicationSupport:nil, sharedDidChange:{})
        return CampusModel(services:services, stack:services.schoolStack(), reminders:.sample(defaults:defaults)) { nil }
    }

    private func setPreferences(_ defaults: SampleDefaults) {
        defaults.set("term", forKey:SpendSpan.storeKey)
        defaults.set("20261114", forKey:TermStartStore.key)
        defaults.set("kept", forKey:"another.key")
    }

    private func assertForgotten(_ defaults: SampleDefaults, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(defaults.object(forKey:SpendSpan.storeKey), file:file, line:line)
        XCTAssertNil(defaults.object(forKey:TermStartStore.key), file:file, line:line)
        XCTAssertEqual(defaults.string(forKey:"another.key"), "kept", file:file, line:line)
        let next = CardRecordsModel(source:SampleData.recordsSource(delay:.milliseconds(1)), preferences:defaults)
        XCTAssertEqual(next.statsSpan, .week, file:file, line:line)
        XCTAssertNil(next.customTermStart, file:file, line:line)
    }

    func testSignOutClearsTheSpanAndTheTermStart() async {
        let defaults = SampleDefaults()
        let campus = campus(defaults:defaults)
        setPreferences(defaults)

        campus.signOut()
        await campus.signOutsFinished()

        XCTAssertFalse(campus.signOutFailed)
        assertForgotten(defaults)
    }

    /// Still signed in after a failed sign-out: their span and term start stay.
    func testAFailedSignOutKeepsTheSpanAndTheTermStart() async throws {
        let store = ScriptedStore()
        try StoredSchoolVault(store:store).saveAccount(SchoolAccount(account:"99100991"))
        let defaults = SampleDefaults()
        let campus = campus(store, defaults:defaults)
        setPreferences(defaults)
        store.refusing = [.schoolPassword]

        campus.signOut()
        await campus.signOutsFinished()

        XCTAssertTrue(campus.signOutFailed)
        XCTAssertEqual(defaults.string(forKey:SpendSpan.storeKey), "term")
        XCTAssertEqual(defaults.string(forKey:TermStartStore.key), "20261114")
    }

    /// The records pages are made again after a sign-out (and per graph): a page left open
    /// keeps none of the person's span or term start in memory.
    func testASignOutGivesTheRecordsPagesANewIdentity() async {
        let defaults = SampleDefaults()
        let campus = campus(defaults:defaults)
        let other = self.campus(defaults:SampleDefaults())
        let before = campus.recordsIdentity
        XCTAssertNotEqual(before, other.recordsIdentity)

        campus.signOut()

        XCTAssertNotEqual(campus.recordsIdentity, before)
        await campus.signOutsFinished()
    }

    /// Someone else signs in without signing out first: the clean-up forgets them too.
    func testAnAccountSwitchClearsTheSpanAndTheTermStart() async {
        let defaults = SampleDefaults()
        let campus = campus(defaults:defaults)
        setPreferences(defaults)

        await campus.previousPersonCleared(unconfirmed:false, dormAndMeterCleared:false, since:campus.signOutGeneration)

        assertForgotten(defaults)
    }

    /// A clean-up overtaken by a sign-out (or a later sign-in) leaves what is stored now alone.
    func testAnOvertakenSwitchLeavesThemAlone() async {
        let defaults = SampleDefaults()
        let campus = campus(defaults:defaults)
        setPreferences(defaults)

        await campus.previousPersonCleared(unconfirmed:false, dormAndMeterCleared:false, since:campus.signOutGeneration - 1)

        XCTAssertEqual(defaults.string(forKey:SpendSpan.storeKey), "term")
        XCTAssertEqual(defaults.string(forKey:TermStartStore.key), "20261114")
    }
}
