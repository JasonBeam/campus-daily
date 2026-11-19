import SwiftUI

/// The home date title: 24 serif semibold in 暖橙, 28 bold in 清爽.
struct ThemeTitleFont: Sendable {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    static let warm = ThemeTitleFont(size:24, weight:.semibold, design:.serif)
    static let clear = ThemeTitleFont(size:28, weight:.bold, design:.default)
}
