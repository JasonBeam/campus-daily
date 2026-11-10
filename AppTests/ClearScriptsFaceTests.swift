import XCTest
import Core
@testable import XiaoRiChang

/// 清爽's small widget draws the POWER / CARD face whenever it has numbers; signed out, waiting
/// for the first read, an expired login, the medium size and 暖橙 keep their own faces.
final class ClearScriptsFaceTests: XCTestCase {
    func model(_ state: WidgetFreshness, numbers: Bool = true) -> CampusWidgetModel {
        CampusWidgetModel(state: state, remainingKWh: numbers ? Decimal(string: "42.6") : nil,
                          balance: numbers ? Decimal(string: "86.5") : nil)
    }

    func testClearSmallWithNumbers() {
        XCTAssertTrue(ClearScriptsFace.draws(model(.fresh), medium: false, theme: .clear))
        XCTAssertTrue(ClearScriptsFace.draws(model(.stale), medium: false, theme: .clear))
    }

    func testOtherFacesKeepTheirOwn() {
        XCTAssertFalse(ClearScriptsFace.draws(model(.fresh), medium: false, theme: .warm), "暖橙")
        XCTAssertFalse(ClearScriptsFace.draws(model(.fresh), medium: true, theme: .clear), "medium")
        XCTAssertFalse(ClearScriptsFace.draws(model(.expired), medium: false, theme: .clear), "expired")
        XCTAssertFalse(ClearScriptsFace.draws(.never, medium: false, theme: .clear), "signed out")
        XCTAssertFalse(ClearScriptsFace.draws(model(.fresh, numbers: false), medium: false, theme: .clear), "first read")
        XCTAssertFalse(ClearScriptsFace.draws(.placeholderFace, medium: false, theme: .clear), "gallery placeholder")
    }
}
