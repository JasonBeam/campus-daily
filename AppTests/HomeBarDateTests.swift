import XCTest
import UIKit
import Core
@testable import XiaoRiChang

/// 暖橙's home shows the date in the bar once the large date has scrolled under the bar, with
/// the sample's bar above the page or without it. The bar's scroll-edge effect shows with it
/// (`BarDateEdge`), so it says when the date is shown.
@MainActor
final class HomeBarDateTests: XCTestCase {
    func testTheDateShowsInTheBarOnceScrolledUnderIt() async throws {
        try await check(sample: false)
    }

    func testTheDateShowsInTheBarUnderTheSampleBar() async throws {
        try await check(sample: true)
    }

    /// At the largest text size the sample's bar wraps onto three rows: the large date still
    /// shows at rest, not the bar's (its height settles in more than one pass).
    func testTheDateStaysOutOfTheBarAtRestUnderTheWrappedSampleBar() async throws {
        try await check(sample: true, size: .accessibilityExtraExtraExtraLarge)
    }

    private func check(sample: Bool, size: UIContentSizeCategory? = nil) async throws {
        guard #available(iOS 26, *) else { throw XCTSkip("the scroll-edge effect is iOS 26's") }
        let harness = RootHarness(theme: .warm, seenSetup: true)
        addTeardownBlock { @MainActor in harness.close() }
        if let size { harness.window.traitOverrides.preferredContentSizeCategory = size }
        if sample { XCTAssertEqual(harness.sample.enter(), .entered) }
        await pause(1000)
        XCTAssertNil(harness.presented, "home, nothing over it")
        let scroll = try XCTUnwrap(Self.views(of: UIScrollView.self, in: harness.window)
            .max { $0.bounds.height < $1.bounds.height })
        XCTAssertTrue(scroll.topEdgeEffect.isHidden, "at rest the large date shows, not the bar's")

        // Just far enough for the large date (lifted into the bar's row) to pass under the bar;
        // at accessibility sizes it is not lifted and is taller, so further.
        let bar = try XCTUnwrap(Self.views(of: UINavigationBar.self, in: harness.window).first)
        let past = bar.frame.height + 24 + (size == nil ? 0 : 260)
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top + past), animated: false)
        await pause(600)
        XCTAssertFalse(scroll.topEdgeEffect.isHidden, "scrolled under the bar: the bar shows the date")

        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        await pause(600)
        XCTAssertTrue(scroll.topEdgeEffect.isHidden)
    }

    private static func views<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let match = view as? T { found.append(match) }
            queue.append(contentsOf: view.subviews)
        }
        return found
    }
}
