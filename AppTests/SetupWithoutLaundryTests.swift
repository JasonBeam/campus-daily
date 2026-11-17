import XCTest
import Core
@testable import XiaoRiChang

/// First-run setup no longer asks about laundry: laundry is on unless the user said otherwise.
@MainActor
final class SetupWithoutLaundryTests: XCTestCase {
    // MARK: Setup

    /// 暖橙's guide: 登录 → 宿舍 → 水控 → 好了, three dots.
    func testWarmGuideHasNoLaundryPage() {
        XCTAssertEqual(OnboardingView.Step.allCases.map { "\($0)" }, ["login", "dorm", "water", "done"])
        XCTAssertEqual(OnboardingView.dotted, 3)
        XCTAssertEqual(OnboardingView.dotsLabel(.login), "第 1 步，共 3 步")
        XCTAssertEqual(OnboardingView.dotsLabel(.dorm), "第 2 步，共 3 步")
        XCTAssertEqual(OnboardingView.dotsLabel(.water), "第 3 步，共 3 步")
    }

    /// 清爽's checklist: 学校账号 and 选择宿舍与水控 only, counted out of two.
    func testClearChecklistHasNoLaundryRow() {
        let fresh = SetupChecklist(signedIn:false, dorm:nil, laundry:.open, controllerBound:false, controllerChecked:false)
        XCTAssertEqual(fresh.rows, [.account, .dorm])
        XCTAssertEqual(fresh.progress, "已完成 0 / 2")
        let done = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.open, controllerBound:true, controllerChecked:true)
        XCTAssertEqual(done.rows, [.account, .dorm])
        XCTAssertEqual(done.progress, "已完成 2 / 2")
        XCTAssertEqual(done.fraction, 1)
    }

    // MARK: Default

    func testFreshInstallHasLaundryOn() {
        let defaults = Self.defaults()
        XCTAssertTrue(Self.laundry(defaults).schoolEnabled)
        XCTAssertNil(defaults.object(forKey:PreferenceKey.schoolLaundry), "nothing written for the user")
    }

    /// Someone who finished setup before keeps what they chose, on or off.
    func testStoredChoiceIsKept() {
        for answer in [true, false] {
            let defaults = Self.defaults()
            defaults.set(answer, forKey:PreferenceKey.schoolLaundry)
            XCTAssertEqual(Self.laundry(defaults).schoolEnabled, answer)
            XCTAssertEqual(defaults.object(forKey:PreferenceKey.schoolLaundry) as? Bool, answer)
        }
    }

    // MARK: Helpers

    private static func defaults() -> UserDefaults {
        let suite = "xrc.tests.laundryLater.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defaults.removePersistentDomain(forName:suite)
        return defaults
    }

    private static func laundry(_ defaults: UserDefaults) -> LaundryModel {
        let services = CampusServices(kind: .live, secureStore: ScriptedStore(), defaults: defaults, sharedPreferences: nil,
                                      schoolHTTP: SampleHTTPClient(), showerHTTP: SampleHTTPClient(), laundryHTTP: SampleHTTPClient(),
                                      feedbackHTTP: nil, showerTransport: SampleShowerTransport(), leaseFile: nil,
                                      applicationSupport: nil, sharedDidChange: {})
        return LaundryModel(services: services, reminders: Reminders.sample(defaults: defaults), activities: nil)
    }
}
