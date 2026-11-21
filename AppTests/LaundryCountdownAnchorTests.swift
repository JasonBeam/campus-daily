//
//  LaundryCountdownAnchorTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
import Core
@testable import XiaoRiChang

/// The laundry countdown runs to the end anchored where the remaining time was first read: a
/// repeated read doesn't push it later; a new value moves it.
final class LaundryCountdownAnchorTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970:1_793_332_800)

    /// The sample washer's order (synthetic), washing with `remain` seconds left.
    func washing(_ remain: Int) -> LaundryOrder {
        LaundryOrder(id:"demo1", deviceID:"demo-washer", status:LaundryOrderStatus("40"), paid:true, remainSeconds:remain, programID:1)
    }

    func phase(_ record: LaundryCheckout, now: Date) -> LaundryFacts.Phase {
        var facts = LaundryFacts()
        facts.configured = true
        facts.record = record
        return facts.phase(now:now)
    }

    func testRepeatedReadsKeepTheCountdownsEnd() {
        var s = SampleData.laundryCheckout(stage:.active, status:"20", paid:true, remain:nil, created:t0, now:t0)
        s = LaundryReducer.reduce(s, .orderRead(washing(600), at:t0)).0
        s = LaundryReducer.reduce(s, .orderRead(washing(600), at:t0.addingTimeInterval(90))).0
        XCTAssertEqual(phase(s, now:t0.addingTimeInterval(90)), .running(end:t0.addingTimeInterval(600)))
        s = LaundryReducer.reduce(s, .orderRead(washing(500), at:t0.addingTimeInterval(120))).0
        XCTAssertEqual(phase(s, now:t0.addingTimeInterval(120)), .running(end:t0.addingTimeInterval(620)), "a new value re-anchors")
    }
}
