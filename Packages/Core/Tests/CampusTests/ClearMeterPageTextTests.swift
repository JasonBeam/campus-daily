import XCTest
import Core

/// 清爽's meter page: 绑定宿舍电表, one prompt over the picker, the same list header at every level.
final class ClearMeterPageTextTests: XCTestCase {
    func testWords() {
        XCTAssertEqual(ClearMeterPageText.title, "绑定宿舍电表")
        XCTAssertEqual(ClearMeterPageText.section, "宿舍电表")
        XCTAssertEqual(ClearMeterPageText.saved, "电表已保存")
        XCTAssertEqual(ClearMeterPageText.note, "电表与热水水控是独立绑定，核对寝室后再保存。")
        XCTAssertEqual(ClearMeterPageText.searchPrompt, "搜索楼栋或寝室")
        XCTAssertEqual(ClearMeterPageText.confirm, "确认是我的寝室并保存")
        XCTAssertEqual(ClearMeterPageText.rechoose, "重新选择位置")
        XCTAssertEqual(ClearMeterPageText.reading, "正在读取电表信息…")
        XCTAssertEqual(ClearMeterPageText.matching, "正在匹配电表，可以先保存热水宿舍")
        XCTAssertEqual(ClearMeterPageText.retryMatch, "重试匹配电表")
    }

    func testPathLine() {
        XCTAssertEqual(ClearMeterPageText.path([]), "选择校区、楼栋和寝室")
        XCTAssertEqual(ClearMeterPageText.path(["北校区", "东苑公寓", "3栋"]), "北校区 · 东苑公寓 · 3栋")
    }

    func testListHeader() {
        XCTAssertEqual(ClearMeterPageText.listHeader(meters: false), "选择位置")
        XCTAssertEqual(ClearMeterPageText.listHeader(meters: true), "核对电表")
    }
}
