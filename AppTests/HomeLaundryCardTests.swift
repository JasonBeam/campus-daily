import XCTest
import Core
@testable import XiaoRiChang

/// Home's laundry row (暖橙) and tile (清爽): the U净 login while not signed in, 常用洗衣机 while
/// no machine is bound, the laundry page once one is.
@MainActor
final class HomeLaundryCardTests: XCTestCase {

    func testNotSignedInLeadsToTheUjingLogin() {
        var data = HomeData()
        data.laundrySignedIn = false
        data.laundryBound = false
        let card = HomeLaundryCard(data)
        XCTAssertEqual(card, .signedOut)
        XCTAssertEqual(card.action, .ujingLogin)
        // 暖橙
        XCTAssertEqual(card.warmTitle, "洗衣")
        XCTAssertEqual(card.warmSubtitle, "登录 U净 后就能在这里下单")
        XCTAssertEqual(card.warmValue, .action("登录 U净"))
        XCTAssertEqual(card.warmLabel, "洗衣，还没登录 U净，轻点两下去登录")
        // 清爽
        XCTAssertEqual(HomeLaundryCard.clearTitle, "洗衣机")
        XCTAssertEqual(card.clearDetail(machine:nil), "未登录 U净")
        XCTAssertEqual(card.clearValue, .action("登录 U净"))
    }

    func testSignedInWithoutAMachineAsksForTheCode() {
        var data = HomeData()
        data.laundrySignedIn = true
        data.laundryBound = false
        let card = HomeLaundryCard(data)
        XCTAssertEqual(card, .unbound)
        XCTAssertEqual(card.action, .washerSetup)
        XCTAssertEqual(card.warmTitle, "洗衣")
        XCTAssertEqual(card.warmSubtitle, "扫机身上的码来绑定")
        XCTAssertNil(card.warmValue, "nothing on the right")
        XCTAssertEqual(card.warmLabel, "洗衣，扫机身上的码来绑定")
        XCTAssertEqual(card.clearDetail(machine:nil), "扫码绑定常用洗衣机")
        XCTAssertNil(card.clearValue)
    }

    func testBoundOpensTheLaundryPage() {
        var data = HomeData()
        data.laundrySignedIn = true
        data.laundryBound = true
        data.laundryMachine = "3"
        data.laundry = .idle
        let card = HomeLaundryCard(data)
        XCTAssertEqual(card, .bound)
        XCTAssertEqual(card.action, .laundry)
        XCTAssertEqual(card.clearDetail(machine:data.laundryMachine), "常用 · 3号")
    }

    /// The sample is signed in to U净 with a machine: unchanged.
    func testSampleIsBound() {
        XCTAssertEqual(HomeLaundryCard(HomeData.sample()), .bound)
    }
}
