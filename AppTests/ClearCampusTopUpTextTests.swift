//
//  ClearCampusTopUpTextTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/10.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 校园充值's words in both themes. 「打开微信」 copies 「e广工商大办事大厅」 first, then opens
/// WeChat (`CampusTopUpFlow`): the page never does either by itself.
final class ClearCampusTopUpTextTests: XCTestCase {
    func testClearWords() {
        XCTAssertEqual(ClearCampusTopUpText.title, "校园充值")
        XCTAssertEqual(ClearCampusTopUpText.headline, "前往学校官方微信服务")
        XCTAssertEqual(ClearCampusTopUpText.body, "进入“e广工商大办事大厅”后，选择校园卡或电费充值；充值电费时请核对宿舍和金额。")
        XCTAssertEqual(ClearCampusTopUpText.note, "点击后将复制“e广工商大办事大厅”并打开微信；在聊天列表下拉点击该小程序，未显示时可搜索并粘贴。付款和到账以学校官方结果为准；返回后会刷新余额。")
        XCTAssertEqual(ClearCampusTopUpText.openWeChat, "打开微信")
        XCTAssertEqual(ClearCampusTopUpText.copied, "已复制“e广工商大办事大厅”")
        XCTAssertEqual(ClearCampusTopUpText.failed, "未能打开微信，小程序名称已复制；请确认已安装微信后手动打开并搜索。")
    }

    func testWarmWords() {
        XCTAssertEqual(CampusTopUpText.title, "校园充值")
        XCTAssertEqual(CampusTopUpText.headline, "去学校的微信服务充值")
        XCTAssertEqual(CampusTopUpText.body, "校园卡和电费都在学校的「e广工商大办事大厅」里充。进去后选校园卡或电费，付款前核对一下宿舍和金额。")
        XCTAssertEqual(CampusTopUpText.hint, "点了会先复制「e广工商大办事大厅」再打开微信。在聊天列表往下拉，点它就行；没看到的话，点搜索粘贴进去。")
        XCTAssertEqual(CampusTopUpText.openWeChat, "打开微信")
        XCTAssertEqual(CampusTopUpText.copied, "已复制 e广工商大办事大厅")
        XCTAssertEqual(CampusTopUpText.failed, "微信没打开，名字已经复制好了。自己打开微信，点搜索粘贴进去。")
    }

    /// Both themes name what is copied exactly as it goes on the pasteboard.
    func testBothThemesNameWhatIsCopied() {
        for text in [CampusTopUpText.hint, CampusTopUpText.copied, ClearCampusTopUpText.note, ClearCampusTopUpText.copied] {
            XCTAssertTrue(text.contains(CampusTopUp.serviceName), text)
        }
    }

    func testNothingHappensUntilATap() {
        var flow = CampusTopUpFlow()
        XCTAssertEqual(flow.handle(.scene(active:true)), [])
        XCTAssertEqual(flow.handle(.weChatTapped), [.copy(CampusTopUp.serviceName), .open(CampusTopUp.weChat)])
    }
}
