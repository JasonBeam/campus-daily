import XCTest
import Core
@testable import XiaoRiChang

/// First-run setup no longer asks about laundry: laundry is on unless the user said otherwise.
@MainActor
final class SetupWithoutLaundryTests: XCTestCase {
    // MARK: Setup

    /// 暖橙's guide: 登录 → 宿舍 → 好了. No laundry page, and no controller check (it is made at
    /// the first 开始洗澡). Three dots, 选样子 the first: the guide opens on the second.
    func testWarmGuideHasNoLaundryOrCheckPage() {
        XCTAssertEqual(OnboardingView.Step.allCases.map { "\($0)" }, ["login", "dorm", "done"])
        XCTAssertEqual(OnboardingView.dotted, 3)
        XCTAssertEqual(OnboardingView.dotsLabel(.login), "第 2 步，共 3 步")
        XCTAssertEqual(OnboardingView.dotsLabel(.dorm), "第 3 步，共 3 步")
        XCTAssertEqual(OnboardingView.doneNote, "第一次洗澡时，站在水控旁边点开始，会先核对是不是你宿舍的水控。")
        XCTAssertEqual(OnboardingView.skip, "先不设置")
    }

    /// 清爽's checklist: 学校账号 and 选择宿舍与水控 only, counted out of two.
    func testClearChecklistHasNoLaundryRow() {
        let fresh = SetupChecklist(signedIn:false, dorm:nil, controllerBound:false)
        XCTAssertEqual(fresh.rows, [.account, .dorm])
        XCTAssertEqual(fresh.progress, "已完成 0 / 2")
        let done = SetupChecklist(signedIn:true, dorm:"3 栋 108", controllerBound:true)
        XCTAssertEqual(done.rows, [.account, .dorm])
        XCTAssertEqual(done.progress, "已完成 2 / 2")
        XCTAssertEqual(done.fraction, 1)
        XCTAssertEqual(fresh.spokenProgress, "已完成 0 项，共两项")
        XCTAssertEqual(done.spokenProgress, "已完成 2 项，共两项")
        XCTAssertEqual(fresh.hint, "先登录学校账号，再选择宿舍。")
        XCTAssertEqual(done.hint, "宿舍已保存，可以开始使用。")
        XCTAssertEqual(done.button, "完成设置")
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
