import XCTest
import Core
@testable import XiaoRiChang

/// The live model's greyed-out 开始洗澡 says why (`ShowerStartBlock`), and only when it is greyed out.
@MainActor
final class ShowerStartBlockModelTests: XCTestCase {
    func testNoDormIsNotConfigured() async {
        let (shower, _) = liveShowerModel(store:ScriptedStore(), support:try? Fixture.supportWithProfile())
        await shower.reloadProfile()
        XCTAssertFalse(shower.mayStart)
        XCTAssertEqual(shower.startBlock, .notConfigured)
    }

    func testABoundDormStartsWithoutAReason() async throws {
        let store = ScriptedStore()
        try StoredShowerVault(store:store).saveBinding(Fixture.binding)
        let (shower, _) = liveShowerModel(store:store, support:try Fixture.supportWithProfile())
        await shower.reloadProfile()
        await waitUntil { shower.gateRecord != .notLoaded }
        XCTAssertTrue(shower.mayStart)
        XCTAssertNil(shower.startBlock)
    }

    /// 退出登录 held hot water: 核对水控; a sign-out that didn't complete: 去设置 too.
    func testSignOutAndAFailedSignOut() async throws {
        let store = ScriptedStore()
        try StoredShowerVault(store:store).saveBinding(Fixture.binding)
        let (shower, _) = liveShowerModel(store:store, support:try Fixture.supportWithProfile())
        await shower.reloadProfile()
        await waitUntil { shower.gateRecord != .notLoaded }

        shower.holdForSignOut()
        XCTAssertFalse(shower.mayStart)
        XCTAssertEqual(shower.startBlock, .accountChanged)
        XCTAssertTrue(shower.signOutDidNotComplete())
        XCTAssertEqual(shower.startBlock, .signOutUnfinished)
    }

    /// Bound, before the launch's profile load: still loading (a spinner, no reason), not
    /// 「这个版本没带热水配置」.
    func testBeforeTheProfileIsReadItIsLaunching() throws {
        let store = ScriptedStore()
        try StoredShowerVault(store:store).saveBinding(Fixture.binding)
        let (shower, _) = liveShowerModel(store:store, support:try Fixture.supportWithProfile())
        XCTAssertFalse(shower.profileLoaded)
        XCTAssertEqual(shower.startBlock, .launching)
        XCTAssertNil(shower.startBlock?.warm)
    }

    func testNoProfileIsPlatformMissing() async throws {
        let store = ScriptedStore()
        try StoredShowerVault(store:store).saveBinding(Fixture.binding)
        let (shower, _) = liveShowerModel(store:store)
        await shower.reloadProfile()
        XCTAssertTrue(shower.platformMissing)
        XCTAssertEqual(shower.startBlock, .platformMissing)
    }

    /// A record waiting for its check: 「上一次洗澡还没结算完」.
    func testAnUnsettledRecord() async throws {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store:store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(Fixture.awaitingReview)
        let (shower, _) = liveShowerModel(store:store, support:try Fixture.supportWithProfile())
        await shower.reloadProfile()
        await waitUntil { shower.gateRecord != .notLoaded }
        XCTAssertFalse(shower.mayStart)
        XCTAssertEqual(shower.startBlock, .unsettled)
    }

    /// The demo pages draw each reason without an engine.
    func testDemoNames() {
        let (shower, _) = liveShowerModel(store:ScriptedStore())
        HomeView.ShowerPageDemo.apply("sh-detail-block-account", to:shower)
        XCTAssertEqual(shower.startBlock, .accountChanged)
        XCTAssertEqual(shower.demoReadyDorm, SampleData.dorm)
        HomeView.ShowerPageDemo.apply("sh-detail-block-unconfigured", to:shower)
        XCTAssertEqual(shower.startBlock, .notConfigured)
        XCTAssertNil(shower.demoReadyDorm, "drawn without a dorm")
        XCTAssertEqual(HomeView.ShowerPageDemo.record("sh-detail-block-storage"), .idle)
        XCTAssertNil(HomeView.ShowerPageDemo.record("sh-detail-block-nope"))
        XCTAssertEqual(Set(HomeView.ShowerPageDemo.blocks.values), Set(ShowerStartBlock.allCases))
        HomeView.ShowerPageDemo.apply(nil, to:shower)
        XCTAssertEqual(shower.startBlock, .notConfigured, "back to the live model's")
        XCTAssertNil(shower.demoStartBlock)
    }
}
