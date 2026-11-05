import XCTest
import Core

/// 清爽 home's 热水 tile says what 暖橙's home button says for the same state.
final class ShowerTileStatusTests: XCTestCase {
    func status(_ s: ShowerHomeStatus, signedIn: Bool = true, minutes: Int? = 11, cost: Decimal? = Decimal(string: "1.32"),
                issue: String? = nil) -> ShowerTileStatus {
        ShowerTileStatus.of(s, signedIn: signedIn, lastMinutes: minutes, lastCost: cost, issue: issue)
    }

    func testIdleShowsTheLastShower() {
        XCTAssertEqual(status(.idle), ShowerTileStatus(text: "上次 11 分钟 · ¥1.32", shorter: ["11 分钟 · ¥1.32", "¥1.32"]))
        XCTAssertEqual(status(.idle, cost: nil).forms, ["上次 11 分钟", "11 分钟"])
        XCTAssertEqual(status(.idle, minutes: nil).text, "")
        XCTAssertEqual(status(.idle, issue: "没连上水控").forms, ["没连上水控"], "the last start's problem wins, with no shorter form")
    }

    func testRunningStates() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(status(.showering(start)), ShowerTileStatus(text: "正在洗澡", tone: .accent, timerStart: start,
                                                                shorter: [""]), "shorter: the timer alone")
        XCTAssertEqual(status(.settling(start)).text, "正在结算…")
        XCTAssertNil(status(.settling(start)).timerStart)
        XCTAssertEqual(status(.starting).text, "正在连接水控…")
    }

    func testAShowerThatIsOverSaysGoShower() {
        var over = ShowerTileStatus(text: "去洗澡")
        over.spokenText = "去洗澡，上一次洗好了"
        XCTAssertEqual(status(.stopped), over)
    }

    func testUnavailableIsDimmedButOpensItsPage() {
        XCTAssertEqual(status(.unavailable("本校暂未开放")), ShowerTileStatus(text: "本校暂未开放", dimmed: true))
        XCTAssertEqual(status(.unconfigured), ShowerTileStatus(text: "先在设置里选好宿舍", dimmed: true))
    }

    /// Signed out the tile asks for the sign-in, as the home button; a shower going on keeps its words.
    func testSignedOut() {
        XCTAssertEqual(status(.idle, signedIn: false), ShowerTileStatus(text: "登录学校账号", opensSetup: true))
        XCTAssertEqual(status(.unconfigured, signedIn: false).opensSetup, true)
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(status(.showering(start), signedIn: false).text, "正在洗澡")
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
