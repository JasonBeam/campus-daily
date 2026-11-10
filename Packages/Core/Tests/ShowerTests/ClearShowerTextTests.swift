import XCTest
import Core

/// 清爽's 热水洗澡 page: each face's headline, its line, and the footnote under the button.
final class ClearShowerTextTests: XCTestCase {
    func title(_ phase: ShowerPagePhase?, inUse: Bool = false) -> String { ClearShowerText.face(phase, inUse: inUse).title }
    func body(_ phase: ShowerPagePhase?, inUse: Bool = false) -> String { ClearShowerText.face(phase, inUse: inUse).body }

    func testHeadlines() {
        XCTAssertEqual(title(nil), "准备洗澡")
        XCTAssertEqual(title(.connecting), "正在处理")
        XCTAssertEqual(title(.running), "热水已授权")
        XCTAssertEqual(title(.settling), "正在处理")
        XCTAssertEqual(title(.done), "结算完成")
        for phase in [ShowerPagePhase.connectFailed, .denied, .stopped] {
            XCTAssertEqual(title(phase), "本次待核对", "\(phase)")
            XCTAssertTrue(ClearShowerText.face(phase).problem, "\(phase)")
        }
        XCTAssertFalse(ClearShowerText.face(.done).problem)
    }

    func testLines() {
        XCTAssertEqual(body(nil), "准备好了，靠近水控即可开始")
        XCTAssertEqual(body(.connecting), "正在连接并申请授权…")
        XCTAssertEqual(body(.running), "已授权，请按设备出水键")
        XCTAssertEqual(body(.settling), "正在结束并结算…")
        XCTAssertEqual(body(.done), "服务器已确认结算")
        XCTAssertEqual(body(.connectFailed), "蓝牙连接失败，请靠近水控并退出其他水控连接页面")
        XCTAssertEqual(body(.denied, inUse: true), "水控仍在忙，已断开连接；确认停水后请稍后再试")
        XCTAssertEqual(body(.denied), "学校未授权本次用水，未扣费；请稍后再试")
        XCTAssertEqual(body(.stopped), "水控未保留本次授权，结算尚未确认；请核对官方用水记录")
        XCTAssertEqual(body(.stopped, inUse: true), "水控仍在忙，已断开连接；确认停水后请稍后再试")
    }

    func testNotes() {
        XCTAssertEqual(ClearShowerText.note(nil), "授权后，按水控上的出水键。")
        XCTAssertEqual(ClearShowerText.note(.connecting), "授权后，按水控上的出水键。")
        XCTAssertEqual(ClearShowerText.note(.connectFailed), "授权后，按水控上的出水键。")
        XCTAssertEqual(ClearShowerText.note(.running), "结算完成前，请留在水控附近。")
        XCTAssertEqual(ClearShowerText.note(.settling), "结算完成前，请留在水控附近。")
        XCTAssertEqual(ClearShowerText.note(.stopped), "上一笔费用继续保留；确认机身已停水后，可重新检查并开始。")
        XCTAssertNil(ClearShowerText.note(.done))
        XCTAssertNil(ClearShowerText.note(.denied))
    }

    func testButtonsAndCards() {
        XCTAssertEqual(ClearShowerText.start, "开始洗澡")
        XCTAssertEqual(ClearShowerText.busyButton, "正在处理…")
        XCTAssertEqual(ClearShowerText.end, "结束并结算")
        XCTAssertEqual(ClearShowerText.connection, "连接检查与设备信息")
        XCTAssertEqual(ClearShowerText.lastUse, "最近一次用水")
        XCTAssertEqual(ClearShowerText.costMissing, "金额未返回")
    }

    /// The settled face's button reads 开始洗澡 and only takes the page back to its ready face
    /// (the start is a second tap there); the refused face keeps 好, which closes the page.
    func testAnsweredFacesButton() {
        XCTAssertEqual(ClearShowerText.answerButton(.done).title, "开始洗澡")
        XCTAssertFalse(ClearShowerText.answerButton(.done).leavesPage)
        XCTAssertEqual(ClearShowerText.answerButton(.denied).title, "好")
        XCTAssertTrue(ClearShowerText.answerButton(.denied).leavesPage)
    }
}
