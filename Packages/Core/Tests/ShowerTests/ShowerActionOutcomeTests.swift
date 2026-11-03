import XCTest
@testable import Core
import CoreTestSupport

/// What Siri, Shortcuts and the Live Activity say after 开始洗澡 / 结束并结算: the real reason a
/// start or an end did not go through, and an unconfirmed start is not called confirmed.
final class ShowerActionOutcomeTests: XCTestCase {
    func failed(_ reason: ShowerFailureReason, review: Bool = false, device: ShowerDeviceError? = nil) -> ShowerState {
        var s = ShowerState(phase: .failed)
        s.failure = ShowerFailure(reason: reason, needsReview: review, deviceError: device)
        return s
    }

    func testAStartSaysWhetherTheControllerConfirmed() {
        XCTAssertEqual(ShowerActionOutcome.after(start: true, ShowerState(phase: .running), notice: nil), .success(.started))
        XCTAssertEqual(ShowerActionOutcome.after(start: true, ShowerState(phase: .writePending), notice: nil), .success(.startUnconfirmed))
        XCTAssertNotEqual(ShowerActionOutcome.startedText, ShowerActionOutcome.startUnconfirmedText)
        XCTAssertTrue(ShowerActionOutcome.startUnconfirmedText.contains(ShowerDisplay.writeUnconfirmedHint))
    }

    func testAFailedStartCarriesItsReason() {
        XCTAssertEqual(ShowerActionOutcome.after(start: true, failed(.deviceBusy), notice: nil),
                       .failure(ShowerActionFailure("水控正在使用中。")))
        XCTAssertEqual(ShowerActionOutcome.after(start: true, failed(.deviceUnavailable, device: .bluetoothOff), notice: nil),
                       .failure(ShowerActionFailure("蓝牙没开，打开后再试。")), "the device's own reason first")
        XCTAssertEqual(ShowerActionOutcome.after(start: true, failed(.deviceUnavailable), notice: nil),
                       .failure(ShowerActionFailure("没连上水控，靠近一点再试。")))
        XCTAssertEqual(ShowerActionOutcome.after(start: true, failed(.authorizeUncertain, review: true), notice: nil),
                       .failure(ShowerActionFailure("水没开。打开校日常核对一下再开始。")))
        XCTAssertEqual(ShowerActionOutcome.after(start: true, failed(.authorizationInvalid, review: true), notice: nil),
                       .failure(ShowerActionFailure("水没开。打开校日常核对一下再开始。")))
    }

    /// The platform turned the start down (4002, -301): nothing was issued and it gave no words.
    func testADefiniteRefusalSaysTheSchoolDidNotLetTheWaterRun() {
        XCTAssertEqual(ShowerActionOutcome.after(start: true, failed(.authorizeRefused), notice: nil),
                       .failure(ShowerActionFailure("学校没让开水，打开校日常看看。")))
        XCTAssertEqual(ShowerDisplay.failureTitle(ShowerFailure(reason: .authorizeRefused, needsReview: false)), "水没开成")
    }

    func testAnEndSettlesOrSaysWhy() {
        XCTAssertEqual(ShowerActionOutcome.after(start: false, ShowerState(phase: .done), notice: nil), .success(.settled))
        // Back on the timer: the close was not sent.
        XCTAssertEqual(ShowerActionOutcome.after(start: false, ShowerState(phase: .running), notice: "水控没回应，靠近一点再试。"),
                       .failure(ShowerActionFailure("水控没回应，靠近一点再试。")))
        XCTAssertEqual(ShowerActionOutcome.after(start: false, ShowerState(phase: .running), notice: nil),
                       .failure(ShowerActionFailure(ShowerActionOutcome.endNotSentText)))
        XCTAssertEqual(ShowerActionOutcome.after(start: false, failed(.settleUncertain, review: true), notice: nil),
                       .failure(ShowerActionFailure("结算未确认")))
    }

    /// A start turned down for the check of an unclear authorize doesn't call it a settlement.
    func testABlockedStartSaysWhatWaits() {
        var unclear = ShowerFailure(reason: .authorizeUncertain, needsReview: true, error: .rejected(.lxt6, code: "1", message: "余额不足"))
        XCTAssertEqual(ShowerActionFailure.blockedText(unclear), "水没开。学校提示：余额不足。打开校日常核对一下再开始。")
        unclear.error = .uncertain(.lxt6)
        XCTAssertEqual(ShowerActionFailure.blockedText(unclear), "水没开。打开校日常核对一下再开始。")
        XCTAssertEqual(ShowerActionFailure.blockedText(ShowerFailure(reason: .settleUncertain, needsReview: true)),
                       ShowerActionFailure(.blocked).message)
        XCTAssertEqual(ShowerActionFailure.blockedText(nil), ShowerActionFailure(.blocked).message)
    }

    func testEngineRefusalsSayWhatToDo() {
        let all: [ShowerEngineError] = [.busy, .blocked, .notAllowed, .wrongBinding, .storage, .unreadableRecord, .platformMissing]
        let texts = all.map { ShowerActionFailure($0).message }
        XCTAssertEqual(Set(texts).count, all.count, "each its own text")
        XCTAssertFalse(texts.contains(""))
        XCTAssertEqual(ShowerActionFailure(.platformMissing).message, ShowerActionFailure.platformMissingText)
        XCTAssertEqual(ShowerActionFailure("x").errorDescription, "x")
    }
}
