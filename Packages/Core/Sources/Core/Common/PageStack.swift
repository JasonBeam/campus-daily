import Foundation

/// Opening a page on a navigation stack that may already hold pages, without losing what the
/// user left open there.
public enum PageStack {
    /// The stack with `page` showing: as it is when `page` is on top; back to it when it is lower
    /// and every page over it `mayClose`; otherwise `page` pushed on top (an open top-up page is
    /// never closed, it stays under).
    public static func opening<Page: Equatable>(_ page: Page, on stack: [Page], mayClose: (Page) -> Bool) -> [Page] {
        if let index = stack.lastIndex(of:page), stack[(index + 1)...].allSatisfy(mayClose) {
            return Array(stack[...index])
        }
        return stack + [page]
    }

    /// As `opening`, but never a second copy: when `page` is under a page that may not close, the
    /// stack stays as it is (`page` is a back away).
    public static func revealing<Page: Equatable>(_ page: Page, on stack: [Page], mayClose: (Page) -> Bool) -> [Page] {
        guard let index = stack.lastIndex(of:page) else { return stack + [page] }
        return stack[(index + 1)...].allSatisfy(mayClose) ? Array(stack[...index]) : stack
    }

    // MARK: 清爽's pages

    /// Whether `page` may be closed to show another: never a top-up page, nor the laundry page
    /// while an order is between creation and the end of the payment check
    /// (`WidgetLink.mayClosePages`).
    public static func mayClose<Page: StackPage>(_ page: Page, laundry: LaundryPhase?) -> Bool {
        WidgetLink.mayClosePages(rechargeOpen:page.isTopUp, laundryOpen:page.isLaundry, laundry:laundry)
    }

    /// The shower model wants its page (a start, 去核对, a reopen): on top, back to it when it is
    /// lower and nothing over it must stay, otherwise pushed over those pages.
    public static func showingShower<Page: StackPage>(on stack: [Page], laundry: LaundryPhase?) -> [Page] {
        opening(.showerPage, on:stack) { mayClose($0, laundry:laundry) }
    }

    /// What follows the shower page being popped while the model still has it up.
    public enum ShowerLeft: Equatable, Sendable {
        case nothing
        /// Water runs: the page goes down, as 暖橙's ⌄.
        case collapse
        /// It must not be left: pushed back.
        case putBack
    }

    public static func showerLeft<Page: StackPage>(old: [Page], new: [Page], presented: Bool, mayCollapse: Bool) -> ShowerLeft {
        guard old.contains(.showerPage), !new.contains(.showerPage), presented else { return .nothing }
        return mayCollapse ? .collapse : .putBack
    }

    /// Where 「去设置热水」 (after an account switch) goes, and that tab's stack.
    public enum ShowerSetup<Page: StackPage>: Equatable {
        /// 日常 with the shower page.
        case home([Page])
        /// 设置 with the dorm page (no controller bound).
        case settings([Page])
    }

    /// The shower page on 日常 when a controller is bound, else the dorm page on 设置; on the
    /// stack the user left (`revealing`): never a second copy, never closing a page that must stay.
    public static func showerSetup<Page: StackPage>(configured: Bool, home: [Page], settings: [Page],
                                                      laundry: LaundryPhase?) -> ShowerSetup<Page> {
        let closable: (Page) -> Bool = { PageStack.mayClose($0, laundry:laundry) }
        return configured ? .home(revealing(.showerPage, on:home, mayClose:closable))
                          : .settings(revealing(.dormPage, on:settings, mayClose:closable))
    }
}
