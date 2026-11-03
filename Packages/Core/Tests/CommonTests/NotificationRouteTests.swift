import XCTest
@testable import Core

/// A tapped reminder opens the laundry page for laundry, and home for everything else.
final class NotificationRouteTests: XCTestCase {
    func testLaundryOpensTheLaundryPage() {
        XCTAssertEqual(NotificationRoute(userInfo: ["route": "laundry"]), .laundry)
    }

    func testHomeAndUnknownValuesOpenHome() {
        XCTAssertEqual(NotificationRoute(userInfo: ["route": "home"]), .home)
        XCTAssertEqual(NotificationRoute(userInfo: ["route": "records"]), .home)
        XCTAssertEqual(NotificationRoute(userInfo: ["route": 1]), .home)
        XCTAssertEqual(NotificationRoute(userInfo: [:]), .home)
    }

    func testEveryRouteSurvivesItsOwnUserInfo() {
        for route in [NotificationRoute.home, .laundry] {
            XCTAssertEqual(NotificationRoute(userInfo: route.userInfo), route)
        }
    }
}
