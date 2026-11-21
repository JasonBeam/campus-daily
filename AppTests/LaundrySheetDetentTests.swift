//
//  LaundrySheetDetentTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import SwiftUI
import XCTest
@testable import XiaoRiChang

/// 暖橙's laundry sheets: the shorter detent only at standard text sizes; at accessibility sizes
/// they open full height, so 去付款 and 先不付 are on screen without a drag.
final class LaundrySheetDetentTests: XCTestCase {
    func testStandardSizesKeepTheShorterDetent() {
        for size: DynamicTypeSize in [.xSmall, .large, .xxxLarge] {
            XCTAssertEqual(LaundryDetail.sheetDetents(height:420, large:false, textSize:size), [.height(420), .large], "\(size)")
        }
    }

    func testAccessibilitySizesOpenFullHeight() {
        for size: DynamicTypeSize in [.accessibility1, .accessibility3, .accessibility5] {
            XCTAssertEqual(LaundryDetail.sheetDetents(height:420, large:false, textSize:size), [.large], "\(size)")
        }
    }

    func testTallerSheetsStayFullHeight() {
        XCTAssertEqual(LaundryDetail.sheetDetents(height:420, large:true, textSize:.large), [.large])
    }
}
