//
//  LookPickTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import XCTest
@testable import Core

/// 「选一个样子」 is asked of a new user once, before the first-run setup; never of someone
/// upgrading; again after 重置校日常.
final class LookPickTests: XCTestCase {
    private func fresh() -> SampleDefaults { SampleDefaults() }

    func testANewInstallIsAFirstRun() {
        XCTAssertTrue(QuickSetupSeen.isFirstRun(in: fresh(), campusConfigured: false, showerConfigured: false, laundryConfigured: false))
    }

    /// Someone upgrading has seen the setup or set something up: no first run, so no picker,
    /// although the picked flag is not there.
    func testAnUpgradeIsNotAFirstRun() {
        let seen = fresh()
        seen.set(true, forKey: QuickSetupSeen.key)
        XCTAssertFalse(QuickSetupSeen.isFirstRun(in: seen, campusConfigured: false, showerConfigured: false, laundryConfigured: false))
        for (campus, shower, laundry) in [(true, false, false), (false, true, false), (false, false, true)] {
            let firstRun = QuickSetupSeen.isFirstRun(in: fresh(), campusConfigured: campus, showerConfigured: shower,
                                                     laundryConfigured: laundry)
            XCTAssertFalse(firstRun, "\(campus) \(shower) \(laundry)")
            XCTAssertFalse(LookPick.isDue(firstRun: firstRun, in: fresh()))
        }
    }

    func testTheNewUserIsAskedUntilALookIsPicked() {
        let storage = fresh()
        XCTAssertFalse(LookPick.hasPicked(in: storage))
        XCTAssertTrue(LookPick.isDue(firstRun: true, in: storage))
        LookPick.picked(in: storage)
        XCTAssertTrue(LookPick.hasPicked(in: storage))
        XCTAssertFalse(LookPick.isDue(firstRun: true, in: storage), "picked once: not asked again")
        XCTAssertEqual(storage.object(forKey: "xrc.pickedLook") as? Bool, true)
    }

    /// 重置校日常 clears the app's preferences: the look is asked for again.
    func testResetAsksAgain() throws {
        let suite = "look-pick-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        LookPick.picked(in: defaults)
        defaults.set(true, forKey: QuickSetupSeen.key)
        try AppReset.clear(store: InMemorySecureStore(), preferences: defaults, preferencesDomain: suite, shared: nil, files: [])
        XCTAssertFalse(LookPick.hasPicked(in: defaults))
        let firstRun = QuickSetupSeen.isFirstRun(in: defaults, campusConfigured: false, showerConfigured: false, laundryConfigured: false)
        XCTAssertTrue(LookPick.isDue(firstRun: firstRun, in: defaults))
    }
}
