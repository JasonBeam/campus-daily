import XCTest
import SwiftUI
@testable import XiaoRiChang

/// U净's login sheet stacks its code row and agreement at accessibility sizes only.
final class UjingLoginLayoutTests: XCTestCase {
    func testTheSheetStacksAtAccessibilitySizesOnly() {
        for size in DynamicTypeSize.allCases {
            XCTAssertEqual(UjingLoginView.stacked(size), size >= .accessibility1, "\(size)")
        }
        XCTAssertFalse(UjingLoginView.stacked(.xxxLarge))
        XCTAssertTrue(UjingLoginView.stacked(.accessibility5))
        XCTAssertEqual(UjingLoginView.consentText, "我已阅读并同意 U净 服务协议和隐私政策")
    }
}
