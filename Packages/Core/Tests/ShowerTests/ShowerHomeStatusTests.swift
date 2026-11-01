import XCTest
@testable import Core

final class ShowerHomeStatusTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_793_300_000)

    /// Signed out of the school (or the session could not be read) mid-shower: the button
    /// stays the shower's, so ending and settling are still on home.
    func testAShowerInUseKeepsItsButtonWhenSignedOut() {
        for status: ShowerHomeStatus in [.starting, .showering(start), .settling(start), .unresolved("结算")] {
            XCTAssertFalse(status.asksForSchoolSignIn(signedIn: false), "\(status)")
            XCTAssertFalse(status.asksForSchoolSignIn(signedIn: true), "\(status)")
        }
    }

    func testIdleAsksForTheSchoolSignInOnlyWhenSignedOut() {
        for status: ShowerHomeStatus in [.idle, .unconfigured, .unavailable("这里用不了")] {
            XCTAssertTrue(status.asksForSchoolSignIn(signedIn: false), "\(status)")
            XCTAssertFalse(status.asksForSchoolSignIn(signedIn: true), "\(status)")
        }
    }
}
