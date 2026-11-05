import SwiftUI
import UIKit
import Core
import XCTest
@testable import XiaoRiChang

/// 「先看看示例」 shut (`SampleEntryRefused`): its text, `Theme.disabledText`, keeps at least 4.5:1
/// on the page in both themes, light and dark.
final class SampleEntryContrastTests: XCTestCase {
    private func rgb(_ token: ThemeColor, _ theme: AppTheme, _ style: UIUserInterfaceStyle) -> (Double, Double, Double, Double) {
        let color = UIColor(token.color(theme)).resolvedColor(with:UITraitCollection(userInterfaceStyle:style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green:&g, blue:&b, alpha:&a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private func luminance(_ c: (Double, Double, Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    /// Contrast of `fg` (composited over the background) on `bg`.
    private func contrast(_ fg: ThemeColor, on bg: ThemeColor, _ theme: AppTheme, _ style: UIUserInterfaceStyle) -> Double {
        let f = rgb(fg, theme, style), b = rgb(bg, theme, style)
        let over = (f.0 * f.3 + b.0 * (1 - f.3), f.1 * f.3 + b.1 * (1 - f.3), f.2 * f.3 + b.2 * (1 - f.3))
        let (l1, l2) = (luminance(over), luminance((b.0, b.1, b.2)))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testShutEntryTextKeepsFourAndAHalfToOne() {
        for theme in [AppTheme.warm, .clear] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for bg in [Theme.bg, Theme.group] {
                    let ratio = contrast(Theme.disabledText, on:bg, theme, style)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme) \(style.rawValue) \(bg.token)")
                }
            }
        }
    }
}
