import XCTest
import Core

/// 清爽 home's 热水 tile: one short word for each state.
final class ShowerTileStatusTests: XCTestCase {
    func status(_ s: ShowerHomeStatus, signedIn: Bool = true, minutes: Int? = 11, cost: Decimal? = Decimal(string: "1.32"),
                issue: String? = nil) -> ShowerTileStatus {
        ShowerTileStatus.of(s, signedIn: signedIn, lastMinutes: minutes, lastCost: cost, issue: issue)
    }

    func testIdleIsReadyToConnect() {
        XCTAssertEqual(status(.idle), ShowerTileStatus(text: "可连接"))
        XCTAssertEqual(status(.idle, minutes: nil, cost: nil), ShowerTileStatus(text: "可连接"))
        XCTAssertEqual(status(.idle, issue: "没连上水控"), ShowerTileStatus(text: "待核对"), "the last start's problem: to check")
    }

    func testRunningStates() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(status(.showering(start)), ShowerTileStatus(text: "已授权"))
        XCTAssertEqual(status(.settling(start)), ShowerTileStatus(text: "处理中"))
        XCTAssertEqual(status(.starting), ShowerTileStatus(text: "处理中"))
    }

    func testAShowerThatIsOverIsToCheck() {
        XCTAssertEqual(status(.stopped), ShowerTileStatus(text: "待核对"))
    }

    func testNotSetUp() {
        XCTAssertEqual(status(.unconfigured), ShowerTileStatus(text: "待配置"))
        XCTAssertEqual(status(.unavailable("本校暂未开放")), ShowerTileStatus(text: "本校暂未开放", dimmed: true))
    }

    /// Signed out the tile still opens the first-run checklist; a shower going on keeps its word.
    func testSignedOut() {
        XCTAssertEqual(status(.idle, signedIn: false), ShowerTileStatus(text: "待配置", opensSetup: true))
        XCTAssertEqual(status(.unconfigured, signedIn: false).opensSetup, true)
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(status(.showering(start), signedIn: false).text, "已授权")
    }
}

/// The 热水 tile's second line: the dorm while signed in, nothing otherwise.
final class ShowerTileDormLineTests: XCTestCase {
    func testDormWhileSignedIn() {
        XCTAssertEqual(ShowerTileStatus.dormLine("3 栋 108", signedIn: true), "3 栋 108")
    }

    /// Signed out the dorm a demo or a stale profile still has is not shown; with no dorm, no line.
    func testNoLineSignedOutOrWithoutDorm() {
        XCTAssertNil(ShowerTileStatus.dormLine("3 栋 108", signedIn: false))
        XCTAssertNil(ShowerTileStatus.dormLine(nil, signedIn: true))
        XCTAssertNil(ShowerTileStatus.dormLine("", signedIn: true))
    }
}
