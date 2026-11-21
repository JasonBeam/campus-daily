//
//  LaundryDemoBusyTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import XCTest
import Core
@testable import XiaoRiChang

/// A demo's 下单 / 付款 shows its progress lines on its own demo only, then puts it back; a demo
/// a later link put up is left as it is. Nothing is sent (no model is involved).
@MainActor
final class LaundryDemoBusyTests: XCTestCase {
    final class Box { var demo: LaundryDemo? }

    private func waitUntilBusy(_ box: Box) async {
        for _ in 0..<200 where box.demo?.facts.busy != true { try? await Task.sleep(for:.milliseconds(2)) }
    }

    func testSubmitShowsProgressThenThePageAsItWas() async {
        let box = Box()
        box.demo = LaundryDemo.make(.confirmNow)
        let before = box.demo
        let run = Task { await LaundryDemo.runBusy(get:{ box.demo }, set:{ box.demo = $0 }, step:.milliseconds(150)) }
        await waitUntilBusy(box)
        XCTAssertEqual(box.demo?.facts.busy, true)
        XCTAssertEqual(box.demo?.facts.progress, "正在下单…")
        await run.value
        XCTAssertEqual(box.demo?.run, before?.run)
        XCTAssertEqual(box.demo?.facts.busy, false)
        XCTAssertNil(box.demo?.facts.progress)
        XCTAssertEqual(box.demo?.facts.mayCreate, before?.facts.mayCreate)
    }

    func testTheNextDemoIsLeftAlone() async throws {
        let box = Box()
        box.demo = LaundryDemo.make(.confirmNow)
        let run = Task { await LaundryDemo.runBusy(get:{ box.demo }, set:{ box.demo = $0 }, step:.milliseconds(80)) }
        await waitUntilBusy(box)
        let next = LaundryDemo.make(.pay)
        box.demo = next
        await run.value
        XCTAssertEqual(box.demo?.run, next.run, "not put back to the tapped demo")
        XCTAssertEqual(box.demo?.facts.busy, false)
        XCTAssertNil(box.demo?.facts.progress)
        XCTAssertNotNil(box.demo?.facts.record, "the pay sheet's order is still there")
        XCTAssertEqual(box.demo?.sheet, .pay)
    }
}
