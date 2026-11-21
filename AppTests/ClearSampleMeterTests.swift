//
//  ClearSampleMeterTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 清爽's 「电表设置 / 绑定电表」 on the home card: in the sample it is blocked at once with the
/// sample's message, as 暖橙's 「电表」 is; outside it, it opens the meter page.
@MainActor
final class ClearSampleMeterTests: XCTestCase {
    func testTheMeterLinkIsBlockedAtOnceInTheSample() {
        let sample = SampleMode(gate:LiveShowerGate(record:{ .known(.idle) }))
        XCTAssertEqual(sample.enter(), .entered)
        let navigator = ClearNavigator()
        ClearBalanceCard.openMeter(sample:sample, navigator:navigator)
        XCTAssertEqual(navigator.homePath, [], "no page opens")
        XCTAssertEqual(sample.blocked, .bindMeter)
    }

    func testTheMeterLinkOpensTheMeterPageOutsideTheSample() {
        let sample = SampleMode(gate:LiveShowerGate(record:{ .known(.idle) }))
        let navigator = ClearNavigator()
        ClearBalanceCard.openMeter(sample:sample, navigator:navigator)
        XCTAssertEqual(navigator.homePath, [.powerSetup])
        XCTAssertNil(sample.blocked)
    }
}
