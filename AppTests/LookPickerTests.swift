//
//  LookPickerTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 「选一个样子」: picked on first run, the theme is written and its own setup opens; picked in
/// the sample, the theme is the live app's too and stays after leaving it.
@MainActor
final class LookPickerTests: XCTestCase {
    private func store(_ defaults: SampleDefaults, _ theme: AppTheme = .warm) -> ThemeStore {
        let preference = ThemePreference(storage:defaults)
        try? preference.set(theme, under:UnsharedLock())
        return ThemeStore(preference:preference, lock:UnsharedLock(), didChange:{}) { nil }
    }

    func testFirstRunPickWritesTheThemeAndOpensItsSetup() {
        let defaults = SampleDefaults()
        let live = store(defaults)
        let picker = LookPicker(live:live, liveDefaults:defaults)
        picker.present(.firstRun)
        XCTAssertEqual(picker.shown, .firstRun)
        picker.choose(.clear, shownOn:live)
        XCTAssertEqual(live.theme, .clear)
        XCTAssertEqual(ThemePreference(storage:defaults).theme, .clear)
        XCTAssertTrue(LookPick.hasPicked(in:defaults))
        XCTAssertNil(picker.shown)
        XCTAssertTrue(picker.setupDue, "the picked theme's first-run setup opens next")
    }

    /// Picked in the sample: shown there at once, and kept by the live app after the sample.
    func testSamplePickPersists() {
        let liveDefaults = SampleDefaults(), sampleDefaults = SampleDefaults()
        let live = store(liveDefaults), shown = store(sampleDefaults)
        let picker = LookPicker(live:live, liveDefaults:liveDefaults)
        picker.present(.sample)
        XCTAssertEqual(picker.shown, .sample)
        picker.choose(.clear, shownOn:shown)
        XCTAssertEqual(shown.theme, .clear, "the sample shows it")
        XCTAssertEqual(live.theme, .clear, "and the live app keeps it")
        XCTAssertEqual(ThemePreference(storage:liveDefaults).theme, .clear)
        XCTAssertTrue(LookPick.hasPicked(in:liveDefaults))
        XCTAssertNil(picker.shown)
        XCTAssertFalse(picker.setupDue, "no setup opens over the sample")
    }

    /// A new user's root shows the picker, not its setup; the setup opens once a look is picked.
    func testNewUserSeesThePickerBeforeTheSetup() async {
        let harness = RootHarness(theme:.warm, seenSetup:false, pickedLook:false)
        defer { harness.close() }
        await waitUntil { harness.picker.shown != nil }
        XCTAssertEqual(harness.picker.shown, .firstRun)
        await pause(300)
        XCTAssertFalse(harness.coverShown, "the guide waits for the pick")
        harness.picker.choose(.clear, shownOn:harness.graph.theme)
        await waitUntil { harness.navigator?.setup != nil }
        XCTAssertNotNil(harness.navigator?.setup, "清爽's checklist opens")
    }

    /// Someone upgrading (setup seen) never sees it.
    func testUpgraderSeesNoPicker() async {
        let harness = RootHarness(theme:.warm, seenSetup:true, pickedLook:false)
        defer { harness.close() }
        await pause(500)
        XCTAssertNil(harness.picker.shown)
    }

    /// A new user's picker is up from the first frame (no home shows before it); not once picked.
    func testNewUserPickerIsUpFromLaunch() {
        let defaults = SampleDefaults()
        let picker = LookPicker(live:store(defaults), liveDefaults:defaults, firstRun:true)
        XCTAssertEqual(picker.shown, .firstRun)
        picker.withdrawFirstRun()
        XCTAssertNil(picker.shown, "the launch checks can take it back")
        LookPick.picked(in:defaults)
        XCTAssertNil(LookPicker(live:store(defaults), liveDefaults:defaults, firstRun:true).shown, "picked: not again")
        XCTAssertNil(LookPicker(live:store(SampleDefaults()), liveDefaults:SampleDefaults(), firstRun:false).shown, "upgrader")
    }

    /// Withdrawing leaves the sample's picker alone.
    func testWithdrawKeepsTheSamplePicker() {
        let defaults = SampleDefaults()
        let picker = LookPicker(live:store(defaults), liveDefaults:defaults)
        picker.present(.sample)
        picker.withdrawFirstRun()
        XCTAssertEqual(picker.shown, .sample)
    }

    /// Left and right: a coin toss for each appearance, both ways round.
    func testOrderIsDrawnEachTime() {
        XCTAssertEqual(LookPickerView.drawOrder { true }, [.warm, .clear])
        XCTAssertEqual(LookPickerView.drawOrder { false }, [.clear, .warm])
        let draws = Set((0..<200).map { _ in LookPickerView.drawOrder() })
        XCTAssertEqual(draws.count, 2, "both orders come up")
    }

    /// The opening sway: 60 %, 40 %, back to the middle.
    func testWiggleGoesBothWaysAndBack() {
        XCTAssertEqual(LookPickerView.wiggleSteps, [0.6, 0.4, 0.5])
    }
}
