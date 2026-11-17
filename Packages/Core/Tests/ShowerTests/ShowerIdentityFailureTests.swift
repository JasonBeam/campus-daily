import XCTest
@testable import Core

/// Why the hot-water account read failed, as setup says it: the hot-water platform turning it
/// down over the balance, or anything else (the school's hand-off included).
final class ShowerIdentityFailureTests: XCTestCase {
    func testTheHotWaterPlatformTalkingAboutTheBalanceIsALowBalance() {
        for message in ["账户余额不足，请充值后使用", "欠费", "请先充值"] {
            XCTAssertEqual(ShowerIdentityFailure(ServiceError.rejection(.lxt6, code: "1", message: message)), .lowBalance, message)
        }
    }

    func testEverythingElseIsGeneric() {
        let others: [Error] = [
            ServiceError.rejection(.lxt6, code: "1", message: "系统繁忙"),
            ServiceError.rejection(.ecykt, code: "1", message: "余额不足"),
            ServiceError.badRequest(.lxt6),
            ServiceError.malformed(.lxt6, "Data"),
            ServiceError.offline,
            CancellationError(),
        ]
        for error in others { XCTAssertEqual(ShowerIdentityFailure(error), .other, "\(error)") }
    }
}
