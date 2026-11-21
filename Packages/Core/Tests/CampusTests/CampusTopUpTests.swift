//
//  CampusTopUpTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/05.
//

import XCTest
@testable import Core

/// 校园充值: the app copies the name of the school's WeChat service and opens plain WeChat; it
/// never handles money. Which entry goes where, the copied and failure lines, and the one balance
/// refresh after coming back.
final class CampusTopUpTests: XCTestCase {
    func testTheNameAndPlainWeChat() {
        XCTAssertEqual(CampusTopUp.serviceName, "e广工商大办事大厅")
        XCTAssertEqual(CampusTopUp.weChat.absoluteString, "weixin://")
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

    // MARK: The tap

    /// The name goes on the pasteboard first, then plain WeChat opens; the copied line shows.
    func testATapCopiesTheNameThenOpensWeChat() {
        var flow = CampusTopUpFlow()
        XCTAssertEqual(flow.line, .none)
        XCTAssertEqual(flow.handle(.weChatTapped), [.copy("e广工商大办事大厅"), .open(URL(string: "weixin://")!)])
        XCTAssertEqual(flow.line, .copied)
        XCTAssertEqual(flow.handle(.weChatOpened(true)), [])
        XCTAssertEqual(flow.line, .copied, "the copied line stays once WeChat opened")
    }

    /// Nothing opens or is copied by itself, on opening the page or on coming back.
    func testNothingHappensUntilATap() {
        for sample in [false, true] {
            var flow = CampusTopUpFlow(sample: sample)
            var effects: [CampusTopUpEffect] = []
            for event in [CampusTopUpEvent.scene(active: true), .scene(active: false), .scene(active: true)] {
                effects += flow.handle(event)
            }
            XCTAssertEqual(effects, [], "sample: \(sample)")
            XCTAssertEqual(flow.line, .none)
        }
    }

    // MARK: WeChat did not open

    func testWeChatThatDidNotOpenSaysSoOnceAndTheNextTapCopiesAgain() {
        var flow = CampusTopUpFlow()
        _ = flow.handle(.weChatTapped)
        XCTAssertEqual(flow.handle(.weChatOpened(false)), [.announceFailure])
        XCTAssertEqual(flow.line, .weChatFailed, "the failure line takes the copied line's place")
        // The same answer again is not announced twice.
        XCTAssertEqual(flow.handle(.weChatOpened(false)), [])

        XCTAssertEqual(flow.handle(.weChatTapped), [.copy(CampusTopUp.serviceName), .open(CampusTopUp.weChat)])
        XCTAssertEqual(flow.line, .copied, "a new try takes the failure line off")
        XCTAssertEqual(flow.handle(.weChatOpened(false)), [.announceFailure], "and a new failure says it again")
    }

    // MARK: Coming back

    func testComingBackFromWeChatRefreshesTheBalancesOnce() {
        var flow = CampusTopUpFlow()
        _ = flow.handle(.weChatTapped)
        _ = flow.handle(.weChatOpened(true))
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [.refreshBalances])
        // Later trips away and back are not this tap's.
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [], "once")
    }

    /// The scene may leave before `open` answers: the refresh still comes once.
    func testLeavingBeforeOpenAnswersStillRefreshesOnce() {
        var flow = CampusTopUpFlow()
        _ = flow.handle(.weChatTapped)
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.weChatOpened(true)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [.refreshBalances])
        XCTAssertEqual(flow.handle(.scene(active: true)), [])
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
        _ = flow.handle(.weChatTapped)
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [.refreshBalances])
        XCTAssertEqual(flow.handle(.scene(active: true)), [])
    }

    // MARK: 先看看示例

    /// The sample's button works as everywhere else (it touches no account): it copies the name,
    /// opens WeChat and shows the same lines. Only the balances are not read after coming back.
    func testTheSampleCopiesAndOpensButNeverRefreshes() {
        var flow = CampusTopUpFlow(sample: true)
        XCTAssertEqual(flow.handle(.weChatTapped), [.copy("e广工商大办事大厅"), .open(URL(string: "weixin://")!)])
        XCTAssertEqual(flow.line, .copied)
        XCTAssertEqual(flow.handle(.weChatOpened(false)), [.announceFailure])
        XCTAssertEqual(flow.line, .weChatFailed)
        _ = flow.handle(.weChatTapped)
        XCTAssertEqual(flow.handle(.weChatOpened(true)), [])
        XCTAssertEqual(flow.line, .copied)
        XCTAssertEqual(flow.handle(.scene(active: false)), [])
        XCTAssertEqual(flow.handle(.scene(active: true)), [], "the sample reads nothing from the school")
    }
}
