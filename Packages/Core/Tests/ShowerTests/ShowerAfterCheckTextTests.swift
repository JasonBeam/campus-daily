//
//  ShowerAfterCheckTextTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
@testable import Core

/// Right after a first check passed (the 「找到了」), the same start's connecting face says it is
/// asking for the authorization; a normal start keeps the connecting words.
final class ShowerAfterCheckTextTests: XCTestCase {
    let machine = "11223344"

    func reduce(_ flow: inout ShowerPageFlow, _ event: ShowerPageEvent) -> [ShowerPageEffect] {
        let (next, effects) = ShowerPageFlow.reduce(flow, event)
        flow = next
        return effects
    }

    func passedFirstCheck() -> ShowerPageFlow {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .firstCheckTapped)
        var sent = ShowerState(phase: .authorizing, machineID: machine)
        _ = reduce(&flow, .record(sent))
        XCTAssertFalse(flow.afterCheck, "still checking")
        sent.authorizeSent = true
        sent.peripheralID = "P"
        _ = reduce(&flow, .record(sent))
        return flow
    }

    func testAFirstCheckThatPassedShowsTheAuthorizingLine() {
        let flow = passedFirstCheck()
        XCTAssertEqual(flow.checkPassed, 1)
        XCTAssertTrue(flow.afterCheck)
        XCTAssertEqual(flow.page?.phase, .connecting)
        XCTAssertEqual(flow.page?.steps, [.current, .future, .future], "the step bar stays on 连接")
        let face = ClearShowerText.face(.connecting, afterCheck: flow.afterCheck)
        XCTAssertEqual(face.title, "正在处理")
        XCTAssertEqual(face.body, "正在申请授权…")
        XCTAssertFalse(face.problem)
    }

    func testANormalStartKeepsTheConnectingLine() {
        var flow = ShowerPageFlow(record: .idle)
        XCTAssertEqual(reduce(&flow, .startTapped), [.start])
        _ = reduce(&flow, .record(ShowerState(phase: .authorizing, machineID: machine)))
        XCTAssertFalse(flow.afterCheck)
        XCTAssertEqual(flow.page?.phase, .connecting)
        let face = ClearShowerText.face(.connecting, afterCheck: flow.afterCheck)
        XCTAssertEqual(face.title, "正在处理")
        XCTAssertEqual(face.body, "正在连接并申请授权…")
    }

    func testTheNextStartGoesBackToTheConnectingLine() {
        var flow = passedFirstCheck()
        flow.record = .idle
        _ = reduce(&flow, .startTapped)
        XCTAssertFalse(flow.afterCheck)
        flow = passedFirstCheck()
        flow.record = .idle
        _ = reduce(&flow, .firstCheckTapped)
        XCTAssertFalse(flow.afterCheck)
    }
}
