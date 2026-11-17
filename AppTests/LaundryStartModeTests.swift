import XCTest
import Core
@testable import XiaoRiChang

/// 立刻洗衣 in the pay sheet and on the order card: the words, the spoken labels and the demo
/// records the screenshots open on (nothing is started from them).
@MainActor
final class LaundryStartModeTests: XCTestCase {
    func testThePaySheetWords() {
        XCTAssertEqual(LaundryStartCopy.section, "洗衣方式")
        XCTAssertEqual(LaundryStartCopy.normal, "正常洗衣")
        XCTAssertEqual(LaundryStartCopy.normalNote, "付完款，照常到机器上启动。")
        XCTAssertEqual(LaundryStartCopy.immediate + "（" + LaundryStartCopy.trial + "）", "立刻洗衣（试用）")
        XCTAssertEqual(LaundryStartCopy.immediateNotes.map(\.text).joined(),
                       "先放好衣服和洗衣液，关好门。付完款校日常会帮你启动机器；系统可能提前暂停，没启动就回到校日常。下单后 10 分钟内有效，没启动的话去 U净 App 里启动。")
        XCTAssertEqual(LaundryStartCopy.immediateNotes.map(\.symbol), ["tshirt", "arrow.uturn.backward", "clock"])
        XCTAssertEqual(LaundryStartCopy.amountNote, "实际金额以支付宝里显示的为准。")
        XCTAssertTrue(ClearLaundryCopy.caution.hasSuffix(LaundryStartCopy.amountNote))
    }

    /// The second choice says it is a trial, in its label and to VoiceOver.
    func testImmediateLabelSaysTrial() {
        XCTAssertEqual(LaundryStartCopy.immediateLabel, "立刻洗衣（试用）")
        XCTAssertEqual(LaundryPayCopy.Clear.modes.last, LaundryStartCopy.immediateLabel)
        XCTAssertEqual(LaundryStartCopy.immediateSpoken, "立刻洗衣，试用")
    }

    func testTheLineIsSpokenInFullWithANoticePrefix() {
        let refused = LaundryStartLine(kind: .refused, text: "U净 没让启动：设备未关门", detail: "去 U净 App 里启动。")
        XCTAssertEqual(ImmediateStartLine.spoken(refused), "注意，U净 没让启动：设备未关门，去 U净 App 里启动。")
        let sent = LaundryStartLine(kind: .sent, text: "启动指令发出去了，等机器响应。")
        XCTAssertEqual(ImmediateStartLine.spoken(sent), "启动指令发出去了，等机器响应。")
    }

    /// Another U净 account and a price that does not match: their own card lines, spoken with 「注意，」.
    func testAccountAndPriceCardsSayWhy() {
        let account = try! XCTUnwrap(LaundryDemo.make(.nowAccount).facts.startLine)
        XCTAssertEqual(account.text, "这单是另一个 U净 账号下的，没帮你启动。")
        XCTAssertEqual(account.detail, "去那个账号的 U净 App 里启动。")
        XCTAssertEqual(ImmediateStartLine.spoken(account), "注意，这单是另一个 U净 账号下的，没帮你启动。，去那个账号的 U净 App 里启动。")
        let price = try! XCTUnwrap(LaundryDemo.make(.nowPrice).facts.startLine)
        XCTAssertEqual(price.text, "这单的价格对不上，没帮你启动。")
        XCTAssertEqual(price.detail, "去 U净 App 里启动。")
        XCTAssertEqual(ImmediateStartLine.spoken(price), "注意，这单的价格对不上，没帮你启动。，去 U净 App 里启动。")
    }

    /// The line is shared no more: 清爽 says it in the original app's words, 暖橙 keeps its own.
    func testEachThemeHasItsOwnLine() {
        let sent = LaundryDemo.make(.nowSent).facts
        XCTAssertEqual(sent.clearStartLine?.text, "启动指令已提交，等待机器响应；若未启动请到U净核对")
        XCTAssertEqual(sent.startLine?.text, "启动指令发出去了，等机器响应。")
        let expired = LaundryDemo.make(.nowExpired).facts
        XCTAssertEqual(expired.clearStartLine?.text, "本单自动启动已过期，请在U净核对后手动启动")
        XCTAssertNil(expired.clearStartLine?.detail)
        XCTAssertEqual(expired.startLine?.text, "下单超过 10 分钟，没帮你启动。")
        XCTAssertEqual(expired.startLine?.detail, "去 U净 App 里启动。")
        let kinds: [LaundryDemo.Kind] = [.nowUnpaid, .nowReady, .nowChecking, .nowSent, .nowUncertain, .nowUnsupported,
                                         .nowExpired, .nowRefused, .nowAccount, .nowPrice]
        for kind in kinds {
            let facts = LaundryDemo.make(kind).facts
            XCTAssertEqual(facts.clearStartLine?.kind, facts.startLine?.kind, kind.rawValue)
            XCTAssertNotEqual(facts.clearStartLine?.text, facts.startLine?.text, kind.rawValue)
        }
        XCTAssertNil(LaundryDemo.make(.unpaid).facts.clearStartLine, "a normal order has no line")
    }

    func testIcons() {
        XCTAssertEqual(ImmediateStartLine.symbol(.armed), "bolt")
        XCTAssertEqual(ImmediateStartLine.symbol(.ready), "bolt")
        XCTAssertEqual(ImmediateStartLine.symbol(.sent), "paperplane")
        for kind in [LaundryStartLine.Kind.uncertain, .blocked, .refused] {
            XCTAssertEqual(ImmediateStartLine.symbol(kind), "exclamationmark.circle")
        }
    }

    func testDemoRecordsCarryTheirLine() {
        let cases: [(LaundryDemo.Kind, LaundryStartLine.Kind)] = [
            (.nowUnpaid, .armed), (.nowReady, .ready), (.nowChecking, .checking), (.nowSent, .sent),
            (.nowUncertain, .uncertain), (.nowUnsupported, .blocked), (.nowExpired, .blocked), (.nowRefused, .refused),
            (.nowAccount, .blocked), (.nowPrice, .blocked),
        ]
        for (kind, line) in cases {
            let demo = LaundryDemo.make(kind)
            XCTAssertEqual(demo.facts.startLine?.kind, line, kind.rawValue)
            XCTAssertEqual(demo.facts.record?.immediate, true, kind.rawValue)
        }
        XCTAssertEqual(LaundryDemo.make(.nowExpired).facts.startLine?.text, "下单超过 10 分钟，没帮你启动。")
        XCTAssertNil(LaundryDemo.make(.unpaid).facts.startLine, "a normal order has no line")
        let confirmNow = LaundryDemo.make(.confirmNow)
        XCTAssertTrue(confirmNow.immediate)
        XCTAssertEqual(confirmNow.sheet, .confirm)
        XCTAssertFalse(LaundryDemo.make(.confirm).immediate, "the sheet opens on 正常洗衣")
    }
}
