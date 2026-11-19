import XCTest
import Core

/// 清爽's pages as the rules see them: the shower page, the dorm page (where hot water is bound),
/// the top-up pages, the laundry page and plain pages.
private enum Page: StackPage {
    case shower, dorm, laundry, card, power, account, washerSetup
    static var showerPage: Page { .shower }
    static var dormPage: Page { .dorm }
    var isTopUp: Bool { self == .card || self == .power }
    var isLaundry: Bool { self == .laundry }
}

/// Opening pages on 清爽's tab stacks without a second shower page and without closing a page
/// that must stay (a top-up page; the laundry page while an order is being paid).
final class PageStackRulesTests: XCTestCase {
    private let paying: [LaundryPhase] = [.creating, .reconcile, .created, .paying, .verifying]

    // MARK: Which page may close

    func testTopUpPagesNeverClose() {
        for phase in [nil, LaundryPhase.none, .paying] {
            XCTAssertFalse(PageStack.mayClose(Page.card, laundry:phase))
            XCTAssertFalse(PageStack.mayClose(Page.power, laundry:phase))
        }
    }

    func testTheLaundryPageStaysOnlyWhileAnOrderIsBeingPaid() {
        for phase in paying { XCTAssertFalse(PageStack.mayClose(Page.laundry, laundry:phase), "\(phase)") }
        for phase in [nil, LaundryPhase.none, .active, .attention] { XCTAssertTrue(PageStack.mayClose(Page.laundry, laundry:phase)) }
        XCTAssertTrue(PageStack.mayClose(Page.account, laundry:.paying), "an order being paid holds only its page")
    }

    // MARK: The shower page

    func testShowerPagePushedOnceAndBroughtBack() {
        XCTAssertEqual(PageStack.showingShower(on:[Page](), laundry:nil), [.shower])
        XCTAssertEqual(PageStack.showingShower(on:[Page.account], laundry:nil), [.account, .shower])
        XCTAssertEqual(PageStack.showingShower(on:[Page.shower], laundry:nil), [.shower], "already on top: not twice")
        XCTAssertEqual(PageStack.showingShower(on:[Page.shower, .washerSetup], laundry:nil), [.shower],
                       "lower down: back to it")
    }

    func testShowerPageNeverClosesAPageThatMustStay() {
        XCTAssertEqual(PageStack.showingShower(on:[Page.shower, .card], laundry:nil), [.shower, .card, .shower])
        XCTAssertEqual(PageStack.showingShower(on:[Page.shower, .laundry], laundry:.paying), [.shower, .laundry, .shower])
        XCTAssertEqual(PageStack.showingShower(on:[Page.shower, .laundry], laundry:.active), [.shower])
    }

    /// The shower page popped while the model has it up: collapsed while water runs, otherwise
    /// put back; nothing when it wasn't popped or isn't up.
    func testShowerPageLeft() {
        XCTAssertEqual(PageStack.showerLeft(old:[Page.shower], new:[], presented:true, mayCollapse:true), .collapse)
        XCTAssertEqual(PageStack.showerLeft(old:[Page.shower], new:[], presented:true, mayCollapse:false), .putBack)
        XCTAssertEqual(PageStack.showerLeft(old:[Page.shower], new:[], presented:false, mayCollapse:false), .nothing)
        XCTAssertEqual(PageStack.showerLeft(old:[Page.account], new:[], presented:true, mayCollapse:false), .nothing)
        XCTAssertEqual(PageStack.showerLeft(old:[Page.shower, .account], new:[.shower], presented:true, mayCollapse:false),
                       .nothing, "still on the stack")
    }

    // MARK: 去设置热水 (after an account switch)

    func testShowerSetupOpensTheShowerPageOnce() {
        XCTAssertEqual(PageStack.showerSetup(configured:true, home:[Page](), settings:[], laundry:nil), .home([.shower]))
        XCTAssertEqual(PageStack.showerSetup(configured:true, home:[Page.shower], settings:[], laundry:nil), .home([.shower]),
                       "a shower page already up: no second one")
        XCTAssertEqual(PageStack.showerSetup(configured:true, home:[Page.shower, .account], settings:[], laundry:nil),
                       .home([.shower]))
    }

    func testShowerSetupKeepsTopUpAndPayingPages() {
        XCTAssertEqual(PageStack.showerSetup(configured:true, home:[Page.card], settings:[], laundry:nil),
                       .home([.card, .shower]))
        XCTAssertEqual(PageStack.showerSetup(configured:true, home:[Page.laundry], settings:[], laundry:.paying),
                       .home([.laundry, .shower]))
        XCTAssertEqual(PageStack.showerSetup(configured:true, home:[Page.shower, .laundry], settings:[], laundry:.verifying),
                       .home([.shower, .laundry]), "no second shower page over a page being paid: it is a back away")
    }

    func testShowerSetupWithoutBindingOpensTheDormPageOnSettings() {
        XCTAssertEqual(PageStack.showerSetup(configured:false, home:[Page.card], settings:[], laundry:nil), .settings([.dorm]))
        XCTAssertEqual(PageStack.showerSetup(configured:false, home:[], settings:[Page.power], laundry:nil),
                       .settings([.power, .dorm]), "the top-up page stays under")
        XCTAssertEqual(PageStack.showerSetup(configured:false, home:[], settings:[Page.dorm, .account], laundry:nil),
                       .settings([.dorm]))
        XCTAssertEqual(PageStack.showerSetup(configured:false, home:[], settings:[Page.dorm, .power], laundry:nil),
                       .settings([.dorm, .power]), "no second dorm page over a top-up page")
    }

    // MARK: Revealing a page without a second copy

    func testRevealingNeverPushesASecondCopy() {
        let mayClose: (Page) -> Bool = { PageStack.mayClose($0, laundry:nil) }
        XCTAssertEqual(PageStack.revealing(Page.dorm, on:[], mayClose:mayClose), [.dorm])
        XCTAssertEqual(PageStack.revealing(Page.dorm, on:[.dorm], mayClose:mayClose), [.dorm])
        XCTAssertEqual(PageStack.revealing(Page.dorm, on:[.dorm, .account], mayClose:mayClose), [.dorm])
        XCTAssertEqual(PageStack.revealing(Page.dorm, on:[.dorm, .card], mayClose:mayClose), [.dorm, .card])
        XCTAssertEqual(PageStack.revealing(Page.dorm, on:[.card], mayClose:mayClose), [.card, .dorm])
    }
}
