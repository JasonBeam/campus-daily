import XCTest
import Core
@testable import XiaoRiChang

/// 清爽's 校园充值: the words of the page. Opening WeChat stays a tap (`CampusTopUpFlow`): the page
/// never opens it by itself.
final class ClearCampusTopUpTextTests: XCTestCase {
    func testWords() {
        XCTAssertEqual(ClearCampusTopUpText.title, "校园充值")
        XCTAssertEqual(ClearCampusTopUpText.headline, "前往学校官方微信服务")
        XCTAssertEqual(ClearCampusTopUpText.body, "进入“e广工商大办事大厅”后，选择校园卡或电费充值；充值电费时请核对宿舍和金额。")
        XCTAssertEqual(ClearCampusTopUpText.note, "校日常只负责打开学校入口。付款和到账以学校官方结果为准；返回后会刷新余额。")
        XCTAssertEqual(ClearCampusTopUpText.openWeChat, "打开学校微信入口")
        XCTAssertEqual(ClearCampusTopUpText.failed, "未能打开微信，请确认已安装微信，或使用下方官方中转页。")
        XCTAssertEqual(ClearCampusTopUpText.openWeb, "使用学校官方中转页")
        XCTAssertEqual(ClearCampusTopUpText.footnote, "若入口失效，可在微信搜索“e广工商大办事大厅”，或使用学校官方小程序码。")
    }

    func testNothingOpensUntilATap() {
        var flow = CampusTopUpFlow()
        XCTAssertEqual(flow.handle(.scene(active:true)), [])
        XCTAssertEqual(flow.handle(.weChatTapped), [.open(CampusTopUp.weChat)])
    }
}
