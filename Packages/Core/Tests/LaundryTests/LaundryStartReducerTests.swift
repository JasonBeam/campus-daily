import XCTest
import Foundation
@testable import Core

/// 立刻洗衣 in the pure reducer: what is recorded, what each event does to the start record,
/// and the order card's line.
final class LaundryStartReducerTests: XCTestCase {
    typealias R = LaundryReducer
    let t0 = L.t0

    func reduce(_ s: LaundryCheckout, _ e: LaundryEvent) -> (LaundryCheckout, [LaundryEffect]) { R.reduce(s, e) }

    /// Paid 20, seen by the payment poll at `t0 + 20`.
    func paid(immediate: Bool = true) -> (LaundryCheckout, [LaundryEffect]) {
        var s = reduce(.empty, .confirm(L.draft, at: t0, account: "acct-1", immediate: immediate)).0
        s = reduce(s, .created(orderID: L.orderID)).0
        s = reduce(s, .orderRead(L.order("10"), at: t0.addingTimeInterval(1))).0
        s = reduce(s, .paymentMethods([PayChannel(channel: "alipay")], at: t0.addingTimeInterval(2))).0
        s = reduce(s, .returnedFromPayment).0
        return reduce(s, .orderRead(L.order("20"), at: t0.addingTimeInterval(20)))
    }

    func testConfirmRecordsTheChoice() {
        XCTAssertTrue(reduce(.empty, .confirm(L.draft, at: t0, immediate: true)).0.immediate)
        XCTAssertFalse(reduce(.empty, .confirm(L.draft, at: t0)).0.immediate)
    }

    func testPaidImmediateOrderAsksForThePreStartRead() {
        let (s, effects) = paid()
        XCTAssertEqual(effects, [.readStartCheck(id: L.orderID)])
        XCTAssertTrue(s.checkingStart)
        XCTAssertFalse(s.persistable.checkingStart, "not stored")
        let (normal, normalEffects) = paid(immediate: false)
        XCTAssertEqual(normalEffects, [])
        XCTAssertFalse(normal.checkingStart)
    }

    func testAllClearRecordsSentThenStarts() {
        let (s, _) = paid()
        let at = t0.addingTimeInterval(21)
        let (n, effects) = reduce(s, .startCheckRead(L.check(), at: at))
        XCTAssertEqual(n.start, .sent(at: at))
        XCTAssertEqual(effects, [.startWasher(id: L.orderID)])
    }

    /// Only a start that never left goes back to "not tried".
    func testNotNowRevertsOnlyAnUnsentStart() {
        let (s, _) = paid()
        var n = reduce(s, .startCheckRead(L.check(), at: t0.addingTimeInterval(21))).0
        n = reduce(n, .startNotNow).0
        XCTAssertNil(n.start)
        for start in [LaundryStart.accepted(at: t0), .pending(at: t0), .refused(message: "x", at: t0), .blocked(.expired), .started] {
            var c = s
            c.start = start
            XCTAssertEqual(reduce(c, .startNotNow).0.start, start)
        }
    }

    func testStartRepliesNeverResendAndPollTheOrder() {
        let (s, _) = paid()
        let sent = reduce(s, .startCheckRead(L.check(), at: t0.addingTimeInterval(21))).0
        let at = t0.addingTimeInterval(22)
        let (ok, okEffects) = reduce(sent, .startSent(at: at))
        XCTAssertEqual(ok.start, .accepted(at: at))
        XCTAssertEqual(okEffects, [.readOrder(id: L.orderID, after: LaundryCheckout.pollDelays[0])])
        let (unclear, unclearEffects) = reduce(sent, .startFailed(.uncertain(.ujing), at: at))
        XCTAssertEqual(unclear.start, .pending(at: at))
        XCTAssertEqual(unclearEffects, [.readOrder(id: L.orderID, after: LaundryCheckout.pollDelays[0])])
        let refusal = ServiceError.rejected(.ujing, code: "errorMessage", message: "设备未关门")
        XCTAssertEqual(reduce(sent, .startFailed(refusal, at: at)).0.start, .refused(message: "设备未关门", at: at))
        for state in [ok, unclear] {
            XCTAssertEqual(reduce(state, .refresh).1, [.readOrder(id: L.orderID, after: 0)])
            XCTAssertFalse(reduce(state, .startCheckRead(L.check(), at: at)).1.contains(.startWasher(id: L.orderID)))
        }
    }

    func testWashingReadAfterTheStartIsStarted() {
        let (s, _) = paid()
        var n = reduce(s, .startCheckRead(L.check(), at: t0.addingTimeInterval(21))).0
        n = reduce(n, .startSent(at: t0.addingTimeInterval(22))).0
        n = reduce(n, .orderRead(L.order("40", remain: 1800), at: t0.addingTimeInterval(30))).0
        XCTAssertEqual(n.start, .started)
    }

    func testRestoreKeepsTheStartAndDropsTransientFields() {
        var (s, _) = paid()
        s.start = .pending(at: t0)
        let restored = R.restore(s.persistable)
        XCTAssertEqual(restored.start, .pending(at: t0))
        XCTAssertTrue(restored.immediate)
        XCTAssertFalse(restored.checkingStart)
    }

    // MARK: copy

    func line(_ c: LaundryCheckout) -> LaundryStartLine? { LaundryDisplay(c).startLine }

    func testNormalOrderHasNoLine() {
        XCTAssertNil(line(paid(immediate: false).0))
    }

    func testLinesFollowTheCopy() {
        var unpaid = reduce(.empty, .confirm(L.draft, at: t0, immediate: true)).0
        unpaid = reduce(unpaid, .created(orderID: L.orderID)).0
        unpaid = reduce(unpaid, .orderRead(L.order("10"), at: t0)).0
        XCTAssertEqual(line(unpaid), LaundryStartLine(kind: .armed, text: "付完款回到这里，就帮你启动机器。"))

        var (s, _) = paid()
        XCTAssertEqual(line(s), LaundryStartLine(kind: .checking, text: "正在核对机器…"))
        s.checkingStart = false
        XCTAssertEqual(line(s), LaundryStartLine(kind: .ready, text: "已付款，马上帮你启动。"))
        s.start = .sent(at: t0)
        XCTAssertEqual(line(s), LaundryStartLine(kind: .sent, text: "启动指令发出去了，等机器响应。"))
        s.start = .accepted(at: t0)
        XCTAssertEqual(line(s), LaundryStartLine(kind: .sent, text: "启动指令发出去了，等机器响应。"))
        s.start = .pending(at: t0)
        XCTAssertEqual(line(s), LaundryStartLine(kind: .uncertain, text: "不确定机器启动了没有。", detail: "别再启动，去 U净 App 里看看。"))
        for reason in [LaundryStartBlock.unsupported, .offline, .selfClean, .dispenser] {
            s.start = .blocked(reason)
            XCTAssertEqual(line(s), LaundryStartLine(kind: .blocked, text: "这台机器要在 U净 App 里启动。"))
        }
        s.start = .blocked(.expired)
        XCTAssertEqual(line(s), LaundryStartLine(kind: .blocked, text: "下单超过 10 分钟，没帮你启动。", detail: "去 U净 App 里启动。"))
        s.start = .blocked(.account)
        XCTAssertEqual(line(s), LaundryStartLine(kind: .blocked, text: "这单是另一个 U净 账号下的，没帮你启动。",
                                                 detail: "去那个账号的 U净 App 里启动。"))
        s.start = .blocked(.price)
        XCTAssertEqual(line(s), LaundryStartLine(kind: .blocked, text: "这单的价格对不上，没帮你启动。", detail: "去 U净 App 里启动。"))
        s.start = .refused(message: "设备未关门", at: t0)
        XCTAssertEqual(line(s), LaundryStartLine(kind: .refused, text: "U净 没让启动：设备未关门", detail: "去 U净 App 里启动。"))
        s.start = .refused(message: "", at: t0)
        XCTAssertEqual(line(s), LaundryStartLine(kind: .refused, text: "U净 没让启动。", detail: "去 U净 App 里启动。"))
        s.start = .started
        XCTAssertNil(line(s))
        s.start = .accepted(at: t0)
        s.order = L.order("40", remain: 1800)
        XCTAssertNil(line(s), "washing: the existing 洗衣中")
    }

    func testNoticeKindsAreMarked() {
        XCTAssertTrue(LaundryStartLine(kind: .uncertain, text: "x").isNotice)
        XCTAssertTrue(LaundryStartLine(kind: .blocked, text: "x").isNotice)
        XCTAssertTrue(LaundryStartLine(kind: .refused, text: "x").isNotice)
        XCTAssertFalse(LaundryStartLine(kind: .sent, text: "x").isNotice)
        XCTAssertFalse(LaundryStartLine(kind: .ready, text: "x").isNotice)
    }

    // MARK: follow-up reads

    /// The 45-second re-reads run for five minutes from the start request too.
    func testFollowUpWindowRunsFromTheStartRequest() {
        var (s, _) = paid()
        s.checkingStart = false
        let since = try! XCTUnwrap(s.waitingSince)
        let startedAt = since.addingTimeInterval(280)
        s.start = .accepted(at: startedAt)
        s.orderReadAt = since.addingTimeInterval(290)
        let now = since.addingTimeInterval(400)
        XCTAssertNotNil(LaundryFollowUp.nextRead(s, lastAttempt: nil, now: now))
        s.orderReadAt = startedAt.addingTimeInterval(290)
        XCTAssertNil(LaundryFollowUp.nextRead(s, lastAttempt: nil, now: startedAt.addingTimeInterval(300)))
    }
}
