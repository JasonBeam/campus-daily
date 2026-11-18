import XCTest
import Core
@testable import XiaoRiChang

/// Settings and 校园充值 in the sample (`SampleMode`): nothing says signed in, nothing promises
/// a refresh that never comes, and no switch changes.
@MainActor
final class SampleSettingsTests: XCTestCase {
    /// 暖橙's 学校账号 row says 示例账号 in the sample, never 已登录.
    func testWarmAccountRowSaysSampleAccountInTheSample() {
        XCTAssertEqual(AccountText.sampleAccount, "示例账号")
        XCTAssertEqual(AccountText.row(signedIn:true, account:nil, sample:true), "示例账号")
        XCTAssertEqual(AccountText.row(signedIn:false, account:nil, sample:true), "示例账号")
        XCTAssertEqual(AccountText.row(signedIn:true, account:nil, sample:false), "已登录")
        XCTAssertEqual(AccountText.row(signedIn:false, account:nil, sample:false), "去登录")
    }
}
