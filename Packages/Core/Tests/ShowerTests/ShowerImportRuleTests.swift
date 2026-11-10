import XCTest
@testable import Core

/// A hot-water profile may be imported beside an open shower only when it is really missing,
/// not while the launch is still loading the one the session uses.
final class ShowerImportRuleTests: XCTestCase {
    let running = ShowerState(phase: .running, machineID: "11223344", startedAt: Date(timeIntervalSince1970: 1_800_000_000))

    func testNotDuringTheLaunchLoad() {
        XCTAssertFalse(ShowerImportRule.mayImportProfile(running, profileLoaded: false, profileMissing: true, busy: false, storageBlocked: false))
        XCTAssertTrue(ShowerImportRule.mayImportProfile(running, profileLoaded: true, profileMissing: true, busy: false, storageBlocked: false))
    }

    func testNeverOverAWorkingProfileWhileAShowerIsOpen() {
        XCTAssertFalse(ShowerImportRule.mayImportProfile(running, profileLoaded: true, profileMissing: false, busy: false, storageBlocked: false))
        XCTAssertFalse(ShowerImportRule.mayImportProfile(running, profileLoaded: true, profileMissing: true, busy: true, storageBlocked: false))
        XCTAssertFalse(ShowerImportRule.mayImportProfile(running, profileLoaded: true, profileMissing: true, busy: false, storageBlocked: true))
    }

    func testWithNoSessionAsBefore() {
        for s in [ShowerState.idle, ShowerState(phase: .done),
                  ShowerState(phase: .failed, failure: ShowerFailure(reason: .deviceUnavailable, needsReview: false))] {
            XCTAssertTrue(ShowerImportRule.mayImport(s, busy: false, storageBlocked: false), "\(s.phase)")
            XCTAssertTrue(ShowerImportRule.mayImportProfile(s, profileLoaded: false, profileMissing: true, busy: false, storageBlocked: false))
        }
        XCTAssertFalse(ShowerImportRule.mayImport(running, busy: false, storageBlocked: false))
        XCTAssertFalse(ShowerImportRule.mayImport(ShowerState.idle, busy: true, storageBlocked: false))
    }
}
