import Foundation

/// After 重置校日常: the first-run setup still to open, once, by the root that stays. A reset
/// from 清爽 brings the theme back to 暖橙 (the choice is cleared), so 清爽's root, about to be
/// replaced, leaves it to 暖橙's.
public struct ResetSetupDue: Sendable, Equatable {
    public private(set) var isDue = false

    public init() {}

    public mutating func resetFinished() { isDue = true }

    /// True when the setup is now `root`'s to open: one is due and `root` draws the theme shown.
    public mutating func take(root: AppTheme, current: AppTheme) -> Bool {
        guard isDue, root == current else { return false }
        isDue = false
        return true
    }
}
