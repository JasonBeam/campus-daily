import XCTest
@testable import Core

/// 校园充值: the app only opens the school's WeChat service or its web hand-off page; it never
/// handles money. Which entry goes where, the failure line, and the one balance refresh after
/// coming back.
final class CampusTopUpTests: XCTestCase {
    func testTheAddressesAreTheSchoolsOwn() {
        XCTAssertEqual(CampusTopUp.weChat.absoluteString, "weixin://dl/business/?t=I0xUgrvZt1g")
        XCTAssertEqual(CampusTopUp.web.absoluteString, "https://wxmpurl.cn/I0xUgrvZt1g")
        XCTAssertEqual(CampusTopUp.web.scheme, "https")
    }

    // MARK: Entries

    func testTheCardBalanceOpensTheTopUpOnceSignedIn() {
        XCTAssertEqual(CampusTopUpEntry.card(signedIn: true), .topUp)
        XCTAssertEqual(CampusTopUpEntry.card(signedIn: false), .signIn)
    }

    func testTheElectricityBalanceOpensTheTopUpOnlyWithAMeter() {
        XCTAssertEqual(CampusTopUpEntry.power(signedIn: true, meterBound: true), .topUp)
        XCTAssertEqual(CampusTopUpEntry.power(signedIn: true, meterBound: false), .bindMeter)
        XCTAssertEqual(CampusTopUpEntry.power(signedIn: false, meterBound: true), .signIn)
        XCTAssertEqual(CampusTopUpEntry.power(signedIn: false, meterBound: false), .signIn)
    }

    /// 清爽's balance card: both links read 「充值 ›」, under the same conditions as before.
    func testTheClearLinksShowUnderTheSameConditions() {
        XCTAssertEqual(CampusTopUpEntry.link, "充值 ›")
        XCTAssertEqual(CampusTopUpEntry.cardLink(signedIn: true), CampusTopUpEntry.link)
        XCTAssertNil(CampusTopUpEntry.cardLink(signedIn: false))
        XCTAssertEqual(CampusTopUpEntry.powerLink(signedIn: true, meterBound: true), CampusTopUpEntry.link)
        XCTAssertNil(CampusTopUpEntry.powerLink(signedIn: true, meterBound: false))
        XCTAssertNil(CampusTopUpEntry.powerLink(signedIn: false, meterBound: true))
    }

    // MARK: Opening

    func testEachButtonOpensItsAddress() {
        var flow = CampusTopUpFlow()
        XCTAssertEqual(flow.handle(.weChatTapped), [.open(CampusTopUp.weChat)])
        flow = CampusTopUpFlow()
        XCTAssertEqual(flow.handle(.webTapped), [.open(CampusTopUp.web)])
    }

    func testWeChatThatDidNotOpenSaysSoOnceAndClearsOnTheNextTap() {
        var flow = CampusTopUpFlow()
        _ = flow.handle(.weChatTapped)
        XCTAssertFalse(flow.weChatFailed)
        XCTAssertEqual(flow.handle(.weChatOpened(false)), [.announceFailure])
        XCTAssertTrue(flow.weChatFailed)
        // The same answer again is not announced twice.
        XCTAssertEqual(flow.handle(.weChatOpened(false)), [])

        _ = flow.handle(.weChatTapped)
        XCTAssertFalse(flow.weChatFailed, "a new try takes the line off")
        XCTAssertEqual(flow.handle(.weChatOpened(false)), [.announceFailure], "and a new failure says it again")

        _ = flow.handle(.webTapped)
        XCTAssertFalse(flow.weChatFailed, "用网页打开 takes it off too")
    }

    func testWeChatThatOpenedShowsNoFailure() {
        var flow = CampusTopUpFlow()
        _ = flow.handle(.weChatTapped)
        XCTAssertEqual(flow.handle(.weChatOpened(true)), [])
        XCTAssertFalse(flow.weChatFailed)
    }

    // MARK: Coming back

    func testComingBackAfterEitherButtonRefreshesTheBalancesOnce() {
        for tap in [CampusTopUpEvent.weChatTapped, .webTapped] {
            var flow = CampusTopUpFlow()
            _ = flow.handle(tap)
            if tap == .weChatTapped { _ = flow.handle(.weChatOpened(true)) }
            XCTAssertEqual(flow.handle(.scene(active: false)), [])
            XCTAssertEqual(flow.handle(.scene(active: true)), [.refreshBalances], "\(tap)")
            // Later trips away and back are not this button's.
            XCTAssertEqual(flow.handle(.scene(active: false)), [])
            XCTAssertEqual(flow.handle(.scene(active: true)), [], "\(tap): once")
        }
    }

    func testNoRefreshWithoutATapOrWithoutLeaving() {
        var flow = CampusTopUpFlow()
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [], "no button was tapped")

        _ = flow.handle(.weChatTapped)
        XCTAssertEqual(flow.handle(.scene(active: true)), [], "still here: nothing to refresh yet")
        _ = flow.handle(.weChatOpened(false))
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [], "WeChat never opened: this trip is not from it")
    }

    func testTwoTapsBeforeComingBackStillRefreshOnce() {
        var flow = CampusTopUpFlow()
        _ = flow.handle(.weChatTapped)
        _ = flow.handle(.weChatOpened(false))
        _ = flow.handle(.webTapped)
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [.refreshBalances])
        XCTAssertEqual(flow.handle(.scene(active: true)), [])
    }

    /// 先看看示例: the buttons open the same addresses; nothing is read from the school after.
    func testTheSampleOpensButNeverRefreshes() {
        var flow = CampusTopUpFlow(sample: true)
        XCTAssertEqual(flow.handle(.weChatTapped), [.open(CampusTopUp.weChat)])
        XCTAssertEqual(flow.handle(.weChatOpened(false)), [.announceFailure])
        XCTAssertEqual(flow.handle(.webTapped), [.open(CampusTopUp.web)])
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [])
    }
}
