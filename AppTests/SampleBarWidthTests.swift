//
//  SampleBarWidthTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import SwiftUI
import UIKit
import XCTest
import Core
@testable import XiaoRiChang

/// The sample's bar never runs off the screen: at the largest text sizes 「换个样子」 and 「去登录」
/// go under 「示例，不是你的账号」 (and under each other when side by side is still too wide),
/// so the eye, the words and both buttons stay inside the phone's width with 20 pt margins.
@MainActor
final class SampleBarWidthTests: XCTestCase {
    private func size(_ typeSize: DynamicTypeSize, width: CGFloat) -> CGSize {
        let defaults = SampleDefaults()
        let preference = ThemePreference(storage:defaults)
        try? preference.set(.warm, under:UnsharedLock())
        let themes = ThemeStore(preference:preference, lock:UnsharedLock(), didChange:{}) { nil }
        let picker = LookPicker(live:themes, liveDefaults:defaults)
        let bar = SampleBar()
            .environment(SampleMode(gate:LiveShowerGate(record:{ .known(.idle) })))
            .environment(picker).environment(themes)
            .environment(\.dynamicTypeSize, typeSize)
        let host = UIHostingController(rootView:bar)
        return host.sizeThatFits(in:CGSize(width:width, height:CGFloat.greatestFiniteMagnitude))
    }

    func testTheBarFitsThePhoneAtEveryTextSize() {
        // iPhone SE / mini widths up to the Pro Max.
        for width in [320.0, 375, 402, 440] as [CGFloat] {
            for typeSize in DynamicTypeSize.allCases {
                let fitted = size(typeSize, width:width)
                XCTAssertLessThanOrEqual(fitted.width, width + 0.5, "\(typeSize) at \(width) pt")
            }
        }
    }

    /// At the default size it stays one row, as before.
    func testOneRowAtTheDefaultSize() {
        let regular = size(.large, width:402)
        XCTAssertLessThan(regular.height, 60, "one row")
        XCTAssertGreaterThan(size(.accessibility5, width:402).height, regular.height * 2, "wrapped at AX5")
    }
}
