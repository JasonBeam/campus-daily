import SwiftUI
import UIKit
import XCTest
@testable import XiaoRiChang

/// 暖橙's 「看校园卡记录 ›」 is drawn as home's 「全部 ›」 is: accent text and chevron, the same
/// construction, at 15 pt; 12 pt under the line above it; at least 44 pt to tap.
@MainActor
final class ShowerCardRecordsLinkStyleTests: XCTestCase {
    func testTheLinkLooksLikeHomesAllLink() {
        let link = ShowerCardRecordsLink.style, all = HomeView.allRecordsStyle
        XCTAssertEqual(link.color, Theme.accentText)
        XCTAssertEqual(link.color, all.color)
        XCTAssertEqual(link.weight, all.weight)
        XCTAssertEqual(link.chevronWeight, all.chevronWeight)
        XCTAssertEqual(link.spacing, all.spacing)
        XCTAssertEqual(link.size - link.chevronSize, all.size - all.chevronSize)
        XCTAssertEqual(link.size, 15)
    }

    func testTheLinkSitsTwelvePointsUnderItsLine() {
        XCTAssertEqual(ShowerCardRecordsLink.gap, 12)
    }

    func testTheLinkIsAtLeast44PointsTall() {
        for size in [DynamicTypeSize.xSmall, .large, .accessibility3] {
            let link = ShowerCardRecordsLink {}.environment(\.appTheme, .warm).environment(\.dynamicTypeSize, size)
            let fitted = UIHostingController(rootView:link).sizeThatFits(in:CGSize(width:390, height:CGFloat.greatestFiniteMagnitude))
            XCTAssertGreaterThanOrEqual(fitted.height, 44, "\(size)")
        }
    }
}
