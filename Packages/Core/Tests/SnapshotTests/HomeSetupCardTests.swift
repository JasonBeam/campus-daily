import XCTest
import Core

/// 清爽 home's 「继续设置」 card: there until account, dorm and (while on) the washer are set.
final class HomeSetupCardTests: XCTestCase {
    func testGoneWhenEverythingIsSet() {
        XCTAssertNil(HomeSetupCard.detail(signedIn: true, dormSet: true, laundryEnabled: true, laundryBound: true))
        XCTAssertNil(HomeSetupCard.detail(signedIn: true, dormSet: true, laundryEnabled: false, laundryBound: false),
                     "no washer needed while 学校洗衣机 is off")
    }

    func testShownWhileSomethingIsMissing() {
        XCTAssertEqual(HomeSetupCard.detail(signedIn: false, dormSet: true, laundryEnabled: true, laundryBound: true),
                       "学校账号、宿舍和常用洗衣机")
        XCTAssertEqual(HomeSetupCard.detail(signedIn: true, dormSet: false, laundryEnabled: true, laundryBound: true),
                       "学校账号、宿舍和常用洗衣机")
        XCTAssertEqual(HomeSetupCard.detail(signedIn: true, dormSet: true, laundryEnabled: true, laundryBound: false),
                       "学校账号、宿舍和常用洗衣机")
        XCTAssertEqual(HomeSetupCard.detail(signedIn: false, dormSet: false, laundryEnabled: false, laundryBound: false),
                       "学校账号和宿舍")
        XCTAssertEqual(HomeSetupCard.title, "继续设置")
    }
}
