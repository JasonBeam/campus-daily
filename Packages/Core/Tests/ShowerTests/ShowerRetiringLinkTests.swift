import XCTest
@testable import Core
import CoreTestSupport

/// A disconnect callback for a link being let go is that link finishing, never the current
/// step failing, even when the same controller was picked again.
final class ShowerRetiringLinkTests: XCTestCase {
    func testTheRetiringLinkIsRetiredWhicheverStepRuns() {
        XCTAssertEqual(ShowerRetiringLink.disconnected(isRetiring: true, isCurrent: false), .retired)
        XCTAssertEqual(ShowerRetiringLink.disconnected(isRetiring: true, isCurrent: true), .retired)
    }

    func testOnlyTheCurrentLinkIsLost() {
        XCTAssertEqual(ShowerRetiringLink.disconnected(isRetiring: false, isCurrent: true), .lost)
        XCTAssertEqual(ShowerRetiringLink.disconnected(isRetiring: false, isCurrent: false), .unrelated)
    }

    /// The disconnect callback never came, but the old link is down: the reconnect goes on.
    func testAWaitThatTimedOutOnALinkAlreadyDownCountsAsRetired() {
        XCTAssertTrue(ShowerRetiringLink.retiredAfterWait(failedWith: ShowerDeviceError.timedOut, disconnected: true))
        XCTAssertFalse(ShowerRetiringLink.retiredAfterWait(failedWith: ShowerDeviceError.timedOut, disconnected: false))
        // A cancelled start or Bluetooth turned off still ends the connect.
        XCTAssertFalse(ShowerRetiringLink.retiredAfterWait(failedWith: ShowerDeviceError.interrupted, disconnected: true))
        XCTAssertFalse(ShowerRetiringLink.retiredAfterWait(failedWith: ShowerDeviceError.bluetoothOff, disconnected: true))
        XCTAssertFalse(ShowerRetiringLink.retiredAfterWait(failedWith: CancellationError(), disconnected: true))
    }
}
