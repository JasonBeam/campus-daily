import XCTest
import Core

/// Opening a page on a tab whose stack may already hold pages (清爽's 记录 rows opening 洗衣 or
/// 热水 on 日常): the stack the user left is kept.
final class PageStackTests: XCTestCase {
    private func open(_ page: String, on stack: [String]) -> [String] {
        PageStack.opening(page, on:stack) { $0 != "card" && $0 != "power" }
    }

    func testPushedOnAnEmptyStack() {
        XCTAssertEqual(open("laundry", on:[]), ["laundry"])
    }

    func testPushedOverAnOpenTopUpPage() {
        XCTAssertEqual(open("laundry", on:["card"]), ["card", "laundry"])
        XCTAssertEqual(open("shower", on:["power", "powerSetup"]), ["power", "powerSetup", "shower"])
    }

    func testAlreadyOnTopStaysAsItIs() {
        XCTAssertEqual(open("laundry", on:["card", "laundry"]), ["card", "laundry"])
    }

    func testBackToItWhenOnlyClosablePagesAreOverIt() {
        XCTAssertEqual(open("laundry", on:["laundry", "washerSetup"]), ["laundry"])
    }

    /// Going back would close a top-up page: pushed again on top instead.
    func testNeverClosesAPageThatMustStay() {
        XCTAssertEqual(open("laundry", on:["laundry", "card"]), ["laundry", "card", "laundry"])
    }
}
