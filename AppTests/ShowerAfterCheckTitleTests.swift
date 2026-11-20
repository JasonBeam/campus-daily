import XCTest
@testable import XiaoRiChang

/// 暖橙's connecting face right after the first check passed: 「正在打开水控…」 over the same line;
/// a normal start keeps 「正在连接水控…」.
final class ShowerAfterCheckTitleTests: XCTestCase {
    func testTheTitleAfterAFirstCheck() {
        XCTAssertEqual(ShowerPageText.connecting(afterCheck:true), "正在打开水控…")
        XCTAssertEqual(ShowerPageText.connectingBody, "站近一点，蓝牙别关。")
    }

    func testANormalStartKeepsTheConnectingTitle() {
        XCTAssertEqual(ShowerPageText.connecting(afterCheck:false), "正在连接水控…")
        XCTAssertEqual(ShowerPageText.connecting, "正在连接水控…")
    }
}
