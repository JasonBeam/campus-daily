import XCTest
import Foundation
@testable import Core

final class LaundryReducerTests: XCTestCase {
    typealias R = LaundryReducer
    let t0 = L.t0

    func reduce(_ s: LaundryCheckout, _ e: LaundryEvent) -> (LaundryCheckout, [LaundryEffect]) { R.reduce(s, e) }

    var creating: LaundryCheckout { reduce(.empty, .confirm(L.draft, at: t0)).0 }
    func created(_ order: LaundryOrder = L.order("10"), at: Date? = nil) -> LaundryCheckout {
        let (s, fx) = reduce(creating, .created(orderID: L.orderID))
        XCTAssertEqual(fx, [.readOrder(id: L.orderID, after: 0)])
        return reduce(s, .orderRead(order, at: at ?? t0.addingTimeInterval(1))).0
    }
    func paying(at: Date? = nil) -> LaundryCheckout {
        reduce(created(), .paymentMethods([PayChannel(channel: "alipay")], at: at ?? t0.addingTimeInterval(2))).0
    }
    var f2fArgs: PaymentArguments {
        let link = "alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url="
            + "https%3A%2F%2Fopenauth.alipay.com%2Foauth2%2FpublicAppAuthorize.htm%3Fredirect_uri%3Dhttps%253A%252F%252Fwx.zhinengxiyifang.cn%252Fstatic%252FcommonWasher%252Findex.html"
        return PaymentArguments(.object(["url": .string(link)]))
    }

    // MARK: create

    func testConfirmPersistsCreatingThenCreates() {
        let (s, fx) = reduce(.empty, .confirm(L.draft, at: t0))
        XCTAssertEqual(s.phase, .creating)
        XCTAssertEqual(s.createdAt, t0)
        XCTAssertEqual(fx, [.create(L.draft.request)])
        XCTAssertEqual(L.draft.request, OrderRequest(deviceID: L.device, deviceTypeID: 1, storeID: "test-store-01", programID: 1))
        // Only from none.
        XCTAssertEqual(reduce(s, .confirm(L.draft, at: t0)).1, [])
        XCTAssertEqual(reduce(created(), .confirm(L.draft, at: t0)).1, [])
    }

    func testDraftRequiresFreshOrderableSnapshot() {
        XCTAssertNil(LaundryDraft.make(L.snapshot(status: 1), program: L.standard, now: t0))
        XCTAssertNil(LaundryDraft.make(L.snapshot(enabled: false), program: L.standard, now: t0))
        XCTAssertNil(LaundryDraft.make(L.snapshot(active: "X1"), program: L.standard, now: t0))
        XCTAssertNil(LaundryDraft.make(L.snapshot(programs: [L.quick]), program: L.standard, now: t0))
        XCTAssertNil(LaundryDraft.make(L.snapshot(at: t0.addingTimeInterval(5)), program: L.standard, now: t0), "from the future")
        var other = L.snapshot(); other.scan.moduleType = 1; other.info.moduleType = 1
        XCTAssertNil(LaundryDraft.make(other, program: L.standard, now: t0))
        var noStore = L.snapshot(); noStore.info.storeID = nil
        XCTAssertNil(LaundryDraft.make(noStore, program: L.standard, now: t0))
    }

    func testCreateRefusedClearsWithMessage() {
        let e = ServiceError.rejected(.ujing, code: "30010", message: "设备正在使用中")
        let (s, fx) = reduce(creating, .createFailed(e))
        XCTAssertEqual(s.phase, .none)
        XCTAssertEqual(s.notice, .refused(e))
        XCTAssertEqual(fx, [])
        XCTAssertEqual(reduce(creating, .createFailed(.sessionExpired(.ujing))).0.notice, .sessionExpired)
    }

    func testCreateUncertainReconcilesNeverCreatesAgain() {
        let (s, fx) = reduce(creating, .createFailed(.uncertain(.ujing)))
        XCTAssertEqual(s.phase, .reconcile)
        XCTAssertEqual(fx, [.findActiveOrder(qrCode: L.qr, deviceID: L.device)])
        XCTAssertFalse(s.canCreate)
        XCTAssertEqual(reduce(s, .confirm(L.draft, at: t0)).1, [])
        // Bad id in a success reply: same.
        XCTAssertEqual(reduce(creating, .created(orderID: "../x")).0.phase, .reconcile)
        // Cancelled before the request left: nothing created.
        XCTAssertEqual(reduce(creating, .cancelledBeforeSend).0, .empty)
    }

    func testReconcileAdoptsMatchingOrder() {
        let r = reduce(creating, .createFailed(.timedOut)).0
        let (found, fx) = reduce(r, .activeOrderFound(L.orderID))
        XCTAssertEqual(fx, [.readOrder(id: L.orderID, after: 0)])
        let (adopted, fx2) = reduce(found, .orderRead(L.order("10"), at: t0.addingTimeInterval(30)))
        XCTAssertEqual(adopted.phase, .created)
        XCTAssertEqual(adopted.orderID, L.orderID)
        XCTAssertEqual(fx2, [])
        XCTAssertTrue(adopted.canPay)
        // Already paid → active.
        XCTAssertEqual(reduce(found, .orderRead(L.order("20"), at: t0)).0.phase, .active)
    }

    func testReconcileRejectsForeignOrStaleOrder() {
        let found = reduce(reduce(creating, .createFailed(.timedOut)).0, .activeOrderFound(L.orderID)).0
        for o in [L.order("10", device: "other"), L.order("10", program: 2), L.order("10", id: "OTHER1"),
                  L.order("10", createdAt: "2026-10-30T11:50:00+08:00"), L.order("10", createdAt: nil), L.order("10", price: 500)] {
            let (s, fx) = reduce(found, .orderRead(o, at: t0))
            XCTAssertEqual(s.phase, .reconcile)
            XCTAssertEqual(s.notice, .orderMismatch)
            XCTAssertNil(s.orderID)
            XCTAssertEqual(fx, [])
        }
        let none = reduce(reduce(creating, .createFailed(.timedOut)).0, .activeOrderFound(nil)).0
        XCTAssertEqual(none.notice, .orderNotFound)
        XCTAssertEqual(none.phase, .reconcile)
        XCTAssertEqual(reduce(none, .refresh).1, [.findActiveOrder(qrCode: L.qr, deviceID: L.device)])
        XCTAssertEqual(reduce(none, .activeOrderLookupFailed(.offline)).0.notice, .readFailed(.offline))
        let (cleared, fx) = reduce(none, .resolveManually)
        XCTAssertEqual(cleared.phase, .none)
        XCTAssertEqual(fx, [.diagnostic("laundry.resolvedManually")])
    }

    // MARK: price and pay

    func testPriceAboveConfirmedBlocksPayment() {
        let s = created(L.order("10", price: 450))
        XCTAssertEqual(s.notice, .priceChanged)
        XCTAssertFalse(s.canPay)
        XCTAssertEqual(reduce(s, .pay).1, [])
        XCTAssertFalse(created(L.order("10", price: nil)).canPay)
        XCTAssertTrue(created(L.order("10", price: 350)).canPay, "a lower price never pays more than confirmed")
        XCTAssertEqual(LaundryDisplay(s).hint, "价格变了，刷新一下")
    }

    func testPayLoadsMethodsThenPersistsPayingBeforeArguments() {
        let c = created()
        XCTAssertTrue(c.canPay)
        let (afterPay, payFx) = reduce(c, .pay)
        XCTAssertEqual(afterPay, c)
        XCTAssertEqual(payFx, [.loadPaymentMethods(orderID: L.orderID)])
        let at = t0.addingTimeInterval(2)
        let (p, fx) = reduce(c, .paymentMethods([PayChannel(channel: "alipayF2F", branchType: 0), PayChannel(channel: "alipay")], at: at))
        XCTAssertEqual(p.phase, .paying)
        XCTAssertEqual(p.paymentRequestedAt, at)
        XCTAssertEqual(fx, [.requestPaymentArguments(orderID: L.orderID, channel: PayChannel(channel: "alipay"))])
        let none = reduce(c, .paymentMethods([PayChannel(channel: "wechat")], at: at)).0
        XCTAssertEqual(none.notice, .noPayChannel)
        XCTAssertEqual(none.phase, .created)
        XCTAssertEqual(reduce(c, .paymentMethodsFailed(.offline)).0.notice, .readFailed(.offline))
    }

    func testCheckedLaunchAndRefusedLaunch() {
        let p = paying()
        let (l, fx) = reduce(p, .paymentArguments(f2fArgs))
        XCTAssertEqual(l.phase, .paying)
        guard case .launch(.checkout)? = fx.first else { return XCTFail("\(fx)") }
        XCTAssertEqual(reduce(l, .launched(true)).0.phase, .paying)
        let failed = reduce(l, .launched(false)).0
        XCTAssertEqual(failed.phase, .created)
        XCTAssertEqual(failed.notice, .launchFailed)
        XCTAssertFalse(failed.canPay, "a request happened: only the re-pay rule applies")

        let bad = PaymentArguments(.object(["url": .string("https://pay.example.com/x")]))
        let (r, rfx) = reduce(p, .paymentArguments(bad))
        XCTAssertEqual(r.phase, .created)
        XCTAssertEqual(r.notice, .launchRefused(.disallowedLink))
        XCTAssertEqual(rfx, [.diagnostic("pay.launchRefused.disallowedLink")])

        let signed = "method=alipay.trade.app.pay&biz_content=%7B%22total_amount%22%3A%225.00%22%7D"
        XCTAssertEqual(reduce(p, .paymentArguments(PaymentArguments(.object(["orderInfo": .string(signed)])))).0.notice,
                       .launchRefused(.amountMismatch))

        let (q, qfx) = reduce(p, .paymentArguments(PaymentArguments(.object(["skipPay": .bool(true)]))))
        XCTAssertEqual(q.phase, .verifying)
        XCTAssertEqual(qfx, [.readOrder(id: L.orderID, after: 2)])
    }

    func testPaymentFailures() {
        let p = paying()
        let e = ServiceError.rejected(.ujing, code: "30022", message: "订单已超时")
        let refused = reduce(p, .paymentFailed(e)).0
        XCTAssertEqual(refused.phase, .created)
        XCTAssertEqual(refused.notice, .refused(e))
        let (u, fx) = reduce(p, .paymentFailed(.uncertain(.ujing)))
        XCTAssertEqual(u.phase, .verifying)
        XCTAssertEqual(fx, [.readOrder(id: L.orderID, after: 2)])
        let back = reduce(p, .cancelledBeforeSend).0
        XCTAssertEqual(back.phase, .created)
        XCTAssertNil(back.paymentRequestedAt)
        XCTAssertTrue(back.canPay)
    }

    func testVerifyingPollsWithBackoffThenGivesUp() {
        var (s, fx) = reduce(reduce(paying(), .launched(true)).0, .returnedFromPayment)
        XCTAssertEqual(s.phase, .verifying)
        var delays: [TimeInterval] = []
        var t = t0.addingTimeInterval(10)
        while case .readOrder(_, let after)? = fx.first {
            delays.append(after)
            t = t.addingTimeInterval(after)
            (s, fx) = reduce(s, .orderRead(L.order("10"), at: t))
        }
        XCTAssertEqual(delays, LaundryCheckout.pollDelays)
        XCTAssertEqual(delays.reduce(0, +), 59)
        XCTAssertEqual(s.phase, .created)
        XCTAssertEqual(s.notice, .paymentNotConfirmed)
        XCTAssertFalse(s.canPay)
        // Errors keep polling; an expired login stops.
        let v = reduce(reduce(paying(), .launched(true)).0, .returnedFromPayment).0
        XCTAssertEqual(reduce(v, .orderReadFailed(.offline)).1, [.readOrder(id: L.orderID, after: 4)])
        let expired = reduce(v, .orderReadFailed(.sessionExpired(.ujing)))
        XCTAssertEqual(expired.0.notice, .sessionExpired)
        XCTAssertEqual(expired.1, [])
        XCTAssertEqual(reduce(expired.0, .refresh).1, [.readOrder(id: L.orderID, after: 0)])
    }

    func testPaidAndWashingEmitActivityPlan() {
        let v = reduce(reduce(paying(), .launched(true)).0, .returnedFromPayment).0
        let (paid, fx) = reduce(v, .orderRead(L.order("20"), at: t0))
        XCTAssertEqual(paid.phase, .active)
        XCTAssertEqual(fx, [])
        let readAt = t0.addingTimeInterval(600)
        let (washing, wfx) = reduce(paid, .orderRead(L.order("40", remain: 2400), at: readAt))
        XCTAssertEqual(washing.phase, .active)
        XCTAssertEqual(wfx, [.updateActivity(LaundryActivityPlan(orderID: L.orderID, machineName: "测试洗衣机01", programName: "标准洗",
                                                                  endsAt: readAt.addingTimeInterval(2400)))])
        XCTAssertFalse(washing.canCancel)
        XCTAssertFalse(washing.canPay)
    }

    func testTerminalStatuses() {
        let washing = reduce(created(), .orderRead(L.order("40", remain: 60), at: t0)).0
        for code in ["50", "51", "53"] {
            let (s, fx) = reduce(washing, .orderRead(L.order(code), at: t0.addingTimeInterval(100)))
            XCTAssertEqual(s.phase, .none, code)
            XCTAssertEqual(s.lastOutcome, LaundryOutcome(orderID: L.orderID, status: LaundryOrderStatus(code), at: t0.addingTimeInterval(100)))
            XCTAssertEqual(fx, [.endActivity])
            XCTAssertTrue(s.canCreate)
        }
        let (attention, fx) = reduce(washing, .orderRead(L.order("52"), at: t0))
        XCTAssertEqual(attention.phase, .attention)
        XCTAssertEqual(fx, [.endActivity])
        XCTAssertFalse(attention.canCreate, "52 warning stays until acknowledged")
        let ack = reduce(attention, .acknowledge).0
        XCTAssertEqual(ack.phase, .none)
        XCTAssertEqual(ack.lastOutcome?.status.code, "52")
    }

    func testOrderMismatchKeepsRecord() {
        let c = created()
        let (s, fx) = reduce(c, .orderRead(L.order("40", device: "other"), at: t0))
        XCTAssertEqual(s.phase, .created)
        XCTAssertEqual(s.notice, .orderMismatch)
        XCTAssertEqual(fx, [])
        XCTAssertEqual(reduce(c, .orderReadFailed(.sessionExpired(.ujing))).0.notice, .sessionExpired)
    }

    // MARK: re-pay

    func testRepayRule() {
        let requested = t0.addingTimeInterval(2)
        var s = reduce(paying(at: requested), .launched(false)).0
        XCTAssertFalse(s.canRepay(at: requested.addingTimeInterval(30)))
        // An unpaid read only 90 s after the request is not enough.
        s = reduce(s, .orderRead(L.order("10"), at: requested.addingTimeInterval(90))).0
        XCTAssertFalse(s.canRepay(at: requested.addingTimeInterval(130)))
        XCTAssertEqual(reduce(s, .requestRepay(at: requested.addingTimeInterval(130))).0.repayArmed, false)
        // A read after the 2-minute window allows a re-pay, with a second confirmation.
        let readAt = requested.addingTimeInterval(125)
        s = reduce(s, .orderRead(L.order("17"), at: readAt)).0
        let now = readAt.addingTimeInterval(10)
        XCTAssertTrue(s.canRepay(at: now))
        XCTAssertEqual(reduce(s, .confirmRepay(at: now)).1, [], "needs the first tap")
        XCTAssertEqual(reduce(s, .paymentMethods([PayChannel(channel: "alipay")], at: now)).1, [], "not armed")
        let armed = reduce(s, .requestRepay(at: now)).0
        XCTAssertTrue(armed.repayArmed)
        XCTAssertFalse(armed.persistable.repayArmed)
        XCTAssertEqual(reduce(armed, .confirmRepay(at: now)).1, [.diagnostic("pay.repay"), .loadPaymentMethods(orderID: L.orderID)])
        let again = reduce(armed, .paymentMethods([PayChannel(channel: "alipay")], at: now)).0
        XCTAssertEqual(again.phase, .paying)
        XCTAssertEqual(again.paymentRequestedAt, now)
        // A stale read (≥ 5 min) or a paid order: no re-pay.
        XCTAssertFalse(s.canRepay(at: readAt.addingTimeInterval(300)))
        XCTAssertFalse(reduce(s, .orderRead(L.order("10", paid: true), at: now)).0.canRepay(at: now))
    }

    // MARK: cancel

    func testCancelReadsFirstThenPostsOnceThenVerifies() {
        let c = created()
        XCTAssertTrue(c.canCancel)
        let (pre, fx) = reduce(c, .cancel)
        XCTAssertEqual(pre.phase, .cancelling)
        XCTAssertFalse(pre.cancelSent)
        XCTAssertEqual(fx, [.readOrder(id: L.orderID, after: 0)])
        let (sent, sfx) = reduce(pre, .orderRead(L.order("10"), at: t0))
        XCTAssertTrue(sent.cancelSent)
        XCTAssertEqual(sfx, [.cancelOrder(id: L.orderID)])
        XCTAssertEqual(reduce(sent, .cancelAcknowledged).1, [.readOrder(id: L.orderID, after: 0)])
        let (done, dfx) = reduce(sent, .orderRead(L.order("53"), at: t0))
        XCTAssertEqual(done.phase, .none)
        XCTAssertEqual(dfx, [.endActivity])
        // Still unpaid after the POST: poll, never POST again.
        var (s, pfx) = reduce(sent, .orderRead(L.order("10"), at: t0))
        var count = 0
        while case .readOrder? = pfx.first { (s, pfx) = reduce(s, .orderRead(L.order("10"), at: t0)); count += 1 }
        XCTAssertFalse(pfx.contains(.cancelOrder(id: L.orderID)))
        XCTAssertEqual(count, LaundryCheckout.pollDelays.count - 1)
        XCTAssertEqual(s.phase, .cancelling)
        XCTAssertEqual(s.notice, .cancelUnconfirmed)
    }

    func testCancelOnlyFromUnpaidAndFailures() {
        XCTAssertFalse(reduce(created(), .orderRead(L.order("20"), at: t0)).0.canCancel)
        XCTAssertEqual(reduce(paying(), .cancel).1, [])
        // Paid between the tap and the pre-check: no POST.
        let pre = reduce(created(), .cancel).0
        let (paid, fx) = reduce(pre, .orderRead(L.order("20"), at: t0))
        XCTAssertEqual(paid.phase, .active)
        XCTAssertEqual(paid.notice, .cancelNotAllowed)
        XCTAssertEqual(fx, [])
        XCTAssertEqual(reduce(pre, .orderReadFailed(.offline)).0.phase, .created)

        let sent = reduce(pre, .orderRead(L.order("10"), at: t0)).0
        let e = ServiceError.rejected(.ujing, code: "30031", message: "订单已支付，无法取消")
        let refused = reduce(sent, .cancelFailed(e)).0
        XCTAssertEqual(refused.phase, .created)
        XCTAssertEqual(refused.notice, .refused(e))
        XCTAssertFalse(refused.cancelSent)
        let (u, ufx) = reduce(sent, .cancelFailed(.uncertain(.ujing)))
        XCTAssertEqual(u.phase, .cancelling)
        XCTAssertEqual(ufx, [.readOrder(id: L.orderID, after: 2)])
        XCTAssertEqual(reduce(sent, .cancelledBeforeSend).0.phase, .created)
    }

    // MARK: relaunch

    func testRestoreEachPhase() {
        XCTAssertEqual(R.restore(nil), .empty)
        XCTAssertEqual(R.restore(creating).phase, .reconcile)
        XCTAssertEqual(R.restore(created()).phase, .created)
        let p = paying()
        let restoredPaying = R.restore(p.persistable)
        XCTAssertEqual(restoredPaying.phase, .verifying)
        XCTAssertEqual(reduce(restoredPaying, .refresh).1, [.readOrder(id: L.orderID, after: 0)])
        let verifying = reduce(p, .returnedFromPayment).0
        XCTAssertEqual(R.restore(verifying).phase, .verifying)
        let active = reduce(created(), .orderRead(L.order("40", remain: 60), at: t0)).0
        XCTAssertEqual(R.restore(active).phase, .active)
        let pre = reduce(created(), .cancel).0
        XCTAssertEqual(R.restore(pre).phase, .created)
        let sent = reduce(pre, .orderRead(L.order("10"), at: t0)).0
        XCTAssertEqual(R.restore(sent).phase, .cancelling)
        XCTAssertTrue(R.restore(sent).cancelSent)
        let attention = reduce(active, .orderRead(L.order("52"), at: t0)).0
        XCTAssertEqual(R.restore(attention).phase, .attention)
        let reconcile = reduce(creating, .createFailed(.timedOut)).0
        XCTAssertEqual(R.restore(reconcile).phase, .reconcile)
        // Nothing restored ever sends a money/state request by itself.
        for s in [creating, p, verifying, sent] {
            let r = R.restore(s.persistable)
            for e in [LaundryEvent.refresh] {
                let fx = reduce(r, e).1
                XCTAssertFalse(fx.contains { if case .create = $0 { return true }; if case .requestPaymentArguments = $0 { return true }; if case .cancelOrder = $0 { return true }; return false })
            }
        }
    }

    func testStatusLabelsAndDisplay() {
        XCTAssertEqual(LaundryOrderStatus("52").label, "机器没启动。去 U净 的订单里看看有没有扣款。")
        XCTAssertTrue(LaundryOrderStatus("17").isAwaitingPayment)
        XCTAssertTrue(LaundryOrderStatus("51").isTerminal)
        XCTAssertEqual(LaundryDisplay(created()).title, "已预约 · 待付款")
        XCTAssertEqual(LaundryDisplay(reduce(creating, .createFailed(.timedOut)).0).title, "核对中")
    }
}
