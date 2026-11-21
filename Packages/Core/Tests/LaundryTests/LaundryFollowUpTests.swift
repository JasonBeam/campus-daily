//
//  LaundryFollowUpTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import XCTest
import Foundation
@testable import Core

/// A paid order that is not washing yet (20, starting, or 40 without a remaining time) has a done
/// reminder time before the washing read arrives (its reads are `LaundryForegroundPoll`'s).
final class LaundryFollowUpTests: XCTestCase {
    typealias R = LaundryReducer
    typealias F = LaundryFollowUp
    let t0 = L.t0

    func reduce(_ s: LaundryCheckout, _ e: LaundryEvent) -> LaundryCheckout { R.reduce(s, e).0 }

    /// Paid, seen at `at` by the verify poll.
    func paid(_ status: String = "20", remain: Int? = nil, at: Date) -> LaundryCheckout {
        var s = reduce(.empty, .confirm(L.draft, at: t0))
        s = reduce(s, .created(orderID: L.orderID))
        s = reduce(s, .orderRead(L.order("10"), at: t0.addingTimeInterval(1)))
        s = reduce(s, .paymentMethods([PayChannel(channel: "alipay")], at: t0.addingTimeInterval(2)))
        s = reduce(s, .returnedFromPayment)
        return reduce(s, .orderRead(L.order(status, remain: remain), at: at))
    }

    func testOnlyPaidOrdersHaveAnExpectedEnd() {
        var s = reduce(.empty, .confirm(L.draft, at: t0))
        XCTAssertNil(F.expectedEnd(s))
        s = reduce(reduce(s, .created(orderID: L.orderID)), .orderRead(L.order("10"), at: t0))
        XCTAssertNil(F.expectedEnd(s))
    }

    func testDoneReminderFallsBackToPaymentTimePlusProgram() {
        let seen = t0.addingTimeInterval(60)
        let s = paid(at: seen)
        XCTAssertEqual(F.expectedEnd(s), seen.addingTimeInterval(45 * 60))
        // Later reads keep the time the payment was first seen.
        let later = reduce(s, .orderRead(L.order("20"), at: seen.addingTimeInterval(45)))
        XCTAssertEqual(F.expectedEnd(later), seen.addingTimeInterval(45 * 60))
        XCTAssertEqual(R.restore(later.persistable).paidAt, seen)
        XCTAssertNil(F.expectedEnd(reduce(later, .orderRead(L.order("50"), at: seen.addingTimeInterval(90)))))
    }
}
