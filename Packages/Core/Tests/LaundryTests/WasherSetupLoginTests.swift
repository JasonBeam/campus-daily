import XCTest
import Core

/// 「扫描机身二维码」 and 「从照片识别」 while signed out of U净: the login first, then straight on.
final class WasherSetupLoginTests: XCTestCase {

    /// Signed out, the rows still answer a tap: the U净 login comes first.
    func testSignedOutTapOpensTheLogin() {
        XCTAssertEqual(WasherSetupFlow.tap(.scan, signedIn: false), .signIn(then: .scan))
        XCTAssertEqual(WasherSetupFlow.tap(.photo, signedIn: false), .signIn(then: .photo))
    }

    func testSignedInTapOpensDirectly() {
        XCTAssertEqual(WasherSetupFlow.tap(.scan, signedIn: true), .open(.scan))
        XCTAssertEqual(WasherSetupFlow.tap(.photo, signedIn: true), .open(.photo))
    }

    /// Being signed out no longer greys the rows; an open order or a running step still does.
    func testOnlyOrderAndBusyDisableTheRows() {
        XCTAssertFalse(WasherSetupFlow.addDisabled(mayImport: true, busy: false))
        XCTAssertTrue(WasherSetupFlow.addDisabled(mayImport: false, busy: false))
        XCTAssertTrue(WasherSetupFlow.addDisabled(mayImport: true, busy: true))
    }

    /// The login went through: straight on to what was tapped.
    func testLoginContinuesToWhatWasTapped() {
        XCTAssertEqual(WasherSetupFlow.afterLogin(pending: .scan, signedIn: true), .scan)
        XCTAssertEqual(WasherSetupFlow.afterLogin(pending: .photo, signedIn: true), .photo)
    }

    /// The login was cancelled: stay on the page, nothing opens.
    func testCancelledLoginOpensNothing() {
        XCTAssertNil(WasherSetupFlow.afterLogin(pending: .scan, signedIn: false))
        XCTAssertNil(WasherSetupFlow.afterLogin(pending: .photo, signedIn: false))
    }

    /// The guide card's own 「登录 U净」 has nothing to continue to.
    func testLoginFromTheGuideOpensNothing() {
        XCTAssertNil(WasherSetupFlow.afterLogin(pending: nil, signedIn: true))
    }
}
