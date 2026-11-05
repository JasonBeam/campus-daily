import XCTest
import Core
@testable import XiaoRiChang

/// 暖橙: while a shower is on, every push of 热水 (home's 最近, 校园卡记录, the home button) opens
/// the timer page instead of the 热水洗澡 screen; with no shower on the screen is pushed as before.
/// (清爽 pushes its own timer page for the route, `ClearDestination`; Core's
/// `ShowerStoppedFlowTests` checks what that page shows.)
final class ShowerRouteTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testAPushOfHotWaterOpensTheTimerPageWhileAShowerIsOn() {
        let on = [ShowerState(phase: .running, machineID: "11223344", startedAt: t0),
                  ShowerState(phase: .writePending, machineID: "11223344", startedAt: t0),
                  ShowerState(phase: .running, machineID: "11223344", startedAt: t0, stateReviewRequired: true),
                  ShowerState(phase: .settling, machineID: "11223344", startedAt: t0),
                  // Kept for the school like a stopped shower: no 热水洗澡 screen to check it on.
                  ShowerState(phase: .failed, machineID: "11223344", startedAt: t0,
                              failure: ShowerFailure(reason: .settleUncertain, needsReview: true))]
        for record in on {
            let page = ShowerPageFlow(record: record)
            let fromRecents = HomeRoute.opened([.shower], over: [], page: page)
            XCTAssertEqual(fromRecents.routes, [], "\(record.phase)")
            XCTAssertTrue(fromRecents.showsPage, "\(record.phase)")
            let fromRecords = HomeRoute.opened([.records, .shower], over: [.records], page: page)
            XCTAssertEqual(fromRecords.routes, [.records], "校园卡记录 stays under the page")
            XCTAssertTrue(fromRecords.showsPage)
        }
    }

    func testHotWaterIsPushedAsBeforeWithNoShowerOn() {
        let idle = ShowerPageFlow(record: .idle)
        let pushed = HomeRoute.opened([.records, .shower], over: [.records], page: idle)
        XCTAssertEqual(pushed.routes, [.records, .shower])
        XCTAssertFalse(pushed.showsPage)
        let harmless = ShowerPageFlow(record: ShowerState(phase: .failed, failure: ShowerFailure(reason: .deviceUnavailable, needsReview: false)))
        XCTAssertEqual(HomeRoute.opened([.shower], over: [], page: harmless).routes, [.shower])
    }

    func testOtherPushesAndPopsPassThrough() {
        let page = ShowerPageFlow(record: ShowerState(phase: .running, machineID: "11223344", startedAt: t0))
        XCTAssertEqual(HomeRoute.opened([.laundry], over: [], page: page).routes, [.laundry])
        XCTAssertFalse(HomeRoute.opened([.laundry], over: [], page: page).showsPage)
        XCTAssertEqual(HomeRoute.opened([], over: [.shower], page: page).routes, [], "a pop")
    }

    /// Home over a stopped or kept shower: 「去洗澡」, read 「去洗澡，上一次洗好了」; it opens
    /// the timer page, whose button is 开始下一次洗澡.
    func testHomeSaysGoShowerOverAKeptShower() {
        XCTAssertEqual(HomeShowerButton.title(.stopped), "去洗澡")
        XCTAssertEqual(HomeShowerButton.spokenTitle(.stopped), "去洗澡，上一次洗好了")
        XCTAssertNil(HomeShowerButton.caption(.stopped), "no second line on home")
    }

    /// 清爽's page over a shower that is over: no 「本次费用 · 结算后显示」 card (the app won't
    /// settle it); 连接检查 stays. Every other face keeps its cost card.
    func testClearsStoppedPageHasNoCostCard() {
        XCTAssertFalse(ClearShowerPage.showsCostCard(.stopped))
        for phase: ShowerPagePhase? in [nil, .connecting, .running, .settling, .done, .connectFailed, .denied] {
            XCTAssertTrue(ClearShowerPage.showsCostCard(phase), "\(String(describing: phase))")
        }
    }

    /// 清爽's page over a shower that is over (stopped on the controller, or kept with its
    /// outcome unknown): no 最近一次用水 card. It names the last shower the app settled, which
    /// reads as the cost of the one that just ended. 连接检查 stays; the start layout keeps it.
    func testClearsStoppedPageHasNoLastUseCard() {
        XCTAssertFalse(ClearShowerPage.showsLastUse(.stopped))
        XCTAssertTrue(ClearShowerPage.showsLastUse(nil))
    }
}
