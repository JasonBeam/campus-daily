import XCTest
import Core

/// The order record can't be stored or read: nothing clears that until the app restarts, so
/// every text for it says to restart, never to wait.
final class LaundryEngineErrorTextTests: XCTestCase {
    func testAStorageFailureAtLoginSaysToRestartTheApp() {
        XCTAssertEqual(LaundryEngineError.storage.loginMessage, "这台手机现在存不了洗衣订单，重启 App 再登录 U净。")
        XCTAssertFalse(LaundryEngineError.storage.loginMessage.contains("等一下"))
    }

    func testAStorageFailureElsewhereSaysToRestartTheAppToo() {
        XCTAssertTrue(LaundryEngineError.storage.message.contains("重启 App"))
        XCTAssertFalse(LaundryEngineError.storage.message.contains("重开"))
    }

    func testOtherFailuresSayTheSameAtLogin() {
        for error in [LaundryEngineError.busy, .notAllowed, .washerChanged] {
            XCTAssertEqual(error.loginMessage, error.message)
        }
    }
}
