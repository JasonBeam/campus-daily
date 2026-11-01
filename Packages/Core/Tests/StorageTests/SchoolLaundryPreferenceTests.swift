import XCTest
import Core

private final class MemoryPreferences: PreferenceStorage {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

final class SchoolLaundryPreferenceTests: XCTestCase {
    func testDefaultsOnUntilTheUserSaysNo() {
        let storage = MemoryPreferences()
        let preference = SchoolLaundryPreference(storage:storage)
        XCTAssertTrue(preference.isOn, "nothing stored: on")
        preference.answer(usesSchoolWashers:true)
        XCTAssertTrue(preference.isOn)
        preference.answer(usesSchoolWashers:false)
        XCTAssertFalse(preference.isOn, "「不用」 turns it off")
        XCTAssertEqual(storage.values[SchoolLaundryPreference.key] as? Bool, false)
    }

    func testSwitchRoundTripsAndOnlyTouchesItsOwnKey() {
        let storage = MemoryPreferences()
        storage.values["xrc.laundry.machines"] = Data([1, 2, 3])
        storage.values[PreferenceKey.reminder("laundryDone")] = true
        let preference = SchoolLaundryPreference(storage:storage)
        preference.set(false)
        XCTAssertFalse(preference.isOn)
        preference.set(true)
        XCTAssertTrue(preference.isOn)
        XCTAssertEqual(storage.values["xrc.laundry.machines"] as? Data, Data([1, 2, 3]), "saved machines kept")
        XCTAssertEqual(storage.values[PreferenceKey.reminder("laundryDone")] as? Bool, true, "reminder value kept")
        XCTAssertEqual(Set(storage.values.keys).subtracting(["xrc.laundry.machines", PreferenceKey.reminder("laundryDone")]),
                       [SchoolLaundryPreference.key])
    }

    func testReadsNumbersStoredByUserDefaults() {
        let storage = MemoryPreferences()
        storage.values[SchoolLaundryPreference.key] = NSNumber(value:false)
        XCTAssertFalse(SchoolLaundryPreference(storage:storage).isOn)
        storage.values[SchoolLaundryPreference.key] = "garbage"
        XCTAssertTrue(SchoolLaundryPreference(storage:storage).isOn, "unreadable value falls back to the default")
    }

    func testUserDefaultsConformance() throws {
        let suite = "xrc.tests.schoolLaundry"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let preference = SchoolLaundryPreference(storage:defaults)
        XCTAssertTrue(preference.isOn)
        preference.set(false)
        XCTAssertFalse(SchoolLaundryPreference(storage:defaults).isOn)
    }

    func testTurningOffWaitsForUnfinishedOrders() {
        XCTAssertTrue(SchoolLaundryPreference.mayTurnOff(checkout:nil, busy:false))
        XCTAssertTrue(SchoolLaundryPreference.mayTurnOff(checkout:LaundryPhase.none, busy:false))
        XCTAssertFalse(SchoolLaundryPreference.mayTurnOff(checkout:LaundryPhase.none, busy:true))
        for phase in LaundryPhase.allCases where phase != .none {
            XCTAssertFalse(SchoolLaundryPreference.mayTurnOff(checkout:phase, busy:false), "\(phase)")
            XCTAssertTrue(SchoolLaundryPreference.switchLocked(isOn:true, checkout:phase, busy:false))
            XCTAssertFalse(SchoolLaundryPreference.switchLocked(isOn:false, checkout:phase, busy:false), "turning on is never blocked")
        }
        XCTAssertFalse(SchoolLaundryPreference.switchLocked(isOn:true, checkout:nil, busy:false))
    }

    func testFooterCopy() {
        XCTAssertEqual(SchoolLaundryPreference.footer(isOn:true, locked:false), "关掉后，首页和提醒里都不显示洗衣。")
        XCTAssertEqual(SchoolLaundryPreference.footer(isOn:false, locked:false), "打开后就能扫码洗衣。")
        XCTAssertEqual(SchoolLaundryPreference.footer(isOn:true, locked:true), "洗衣还有一笔没处理完，处理完再关。")
        XCTAssertEqual(SchoolLaundryPreference.Onboarding.title, "宿舍用学校的洗衣机吗？")
        XCTAssertEqual(SchoolLaundryPreference.Onboarding.yes, "用，接着设置")
        XCTAssertEqual(SchoolLaundryPreference.Onboarding.no, "不用")
        XCTAssertEqual(SchoolLaundryPreference.Onboarding.note, "以后可以在设置里改。")
        XCTAssertEqual(PreferenceKey.schoolLaundry, "xrc.laundry.school")
    }
}
