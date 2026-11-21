//
//  ShowerPageDemoTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import XCTest
import Core
@testable import XiaoRiChang

/// The kept-showers demo pages (DEBUG, synthetic): drawn as a set-up page, opening 订单 on the
/// synthetic list, with rows on the dorm's own controller and on another.
@MainActor
final class ShowerPageDemoTests: XCTestCase {
    func testKeptDemoDrawsASetUpIdlePage() {
        let (model, _) = liveShowerModel(store:ScriptedStore())
        XCTAssertFalse(model.configured)
        HomeView.ShowerPageDemo.apply("sh-detail-kept", to:model)
        XCTAssertEqual(model.demoReadyDorm, SampleData.dorm)
        XCTAssertEqual(model.retainedShown(live:false)?.count, 3)
        HomeView.ShowerPageDemo.apply("sh-detail-kept-list", to:model)
        XCTAssertEqual(model.demoReadyDorm, SampleData.dorm)
        HomeView.ShowerPageDemo.apply(nil, to:model)
        XCTAssertNil(model.demoReadyDorm, "any other demo clears it")
        XCTAssertNil(model.retainedShown(live:false))
    }

    func testDetailDemosDrawTheWarmPageSetUpOnASyntheticRecord() {
        let (model, _) = liveShowerModel(store:ScriptedStore())
        HomeView.ShowerPageDemo.apply("sh-detail-run", to:model)
        XCTAssertEqual(model.demoReadyDorm, SampleData.dorm)
        XCTAssertEqual(model.demoDetailRecord?.canFinish, true, "结束并结算")
        XCTAssertEqual(model.state, .idle, "the model's own record is left alone")
        HomeView.ShowerPageDemo.apply("sh-detail-done", to:model)
        XCTAssertEqual(model.demoDetailRecord?.phase, .done)
        XCTAssertNotNil(model.demoDetailRecord?.receipt?.amount)
        HomeView.ShowerPageDemo.apply("sh-detail-ready", to:model)
        XCTAssertEqual(model.demoDetailRecord, .idle)
        XCTAssertNotNil(HomeView.ShowerPageDemo.record("sh-detail-ready"), "pushes 热水洗澡")
        HomeView.ShowerPageDemo.apply(nil, to:model)
        XCTAssertNil(model.demoDetailRecord, "any other demo clears it")
        XCTAssertNil(model.demoReadyDorm)
    }

    func testKeptDemoOpensOrdersOnTheSyntheticList() {
        XCTAssertEqual(HomeView.ShowerPageDemo.records("sh-detail-kept"), .list)
        XCTAssertEqual(HomeView.ShowerPageDemo.records("sh-detail-kept-list"), .list)
        XCTAssertNil(HomeView.ShowerPageDemo.records("sh-denied"))
        XCTAssertNil(HomeView.ShowerPageDemo.records("sh-detail-stopped"))
    }

    func testKeptDemoRowsNameOnlyAnotherController() {
        let lines = ShowerRetainedText.lines(HomeView.ShowerPageDemo.retained(), reason:ShowerRetainedText.Clear.reason) { _ in "T" }
        XCTAssertEqual(lines, [.init(title:"T", detail:"水控 AABBCCDD · 关水未确认"),
                               .init(title:"T", detail:"停水未结算"),
                               .init(title:"授权未确认", detail:nil)])
    }
}
