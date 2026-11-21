//
//  HomeDateTitleBarTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
import UIKit
import Core
@testable import XiaoRiChang

/// 暖橙's home shows the date in the navigation bar once the date block has scrolled under it.
/// The bar itself must not change when that happens: where the bar's height follows its title
/// (iPhone Duo's vertical bars, where an empty top bar is not drawn), a bar that changes moves the
/// date block back out from under it, and the title and the layout flip on every pass.
@MainActor
final class HomeDateTitleBarTests: XCTestCase {
    func testTheBarStaysTheSameWhenTheDateScrollsUnderIt() async throws {
        let harness = RootHarness(theme: .warm, seenSetup: true)
        addTeardownBlock { @MainActor in harness.close() }
        await pause(800)
        XCTAssertNil(harness.presented, "home, nothing over it")

        let bar = try XCTUnwrap(Self.views(of: UINavigationBar.self, in: harness.window).first)
        let scroll = try XCTUnwrap(Self.views(of: UIScrollView.self, in: harness.window)
            .max { $0.bounds.height < $1.bounds.height })
        let restTitle = bar.topItem?.title
        let restHeight = bar.frame.height

        // Well past the date block, which sits right under the bar.
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y + 160), animated: false)
        await pause(600)
        XCTAssertEqual(bar.topItem?.title, restTitle, "the bar's title does not follow the scroll")
        XCTAssertEqual(bar.frame.height, restHeight, "the bar's height does not follow the scroll")

        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        await pause(600)
        XCTAssertEqual(bar.topItem?.title, restTitle)
        XCTAssertEqual(bar.frame.height, restHeight)
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
